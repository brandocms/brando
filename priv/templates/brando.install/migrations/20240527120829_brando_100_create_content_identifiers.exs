defmodule Brando.Repo.Migrations.CreateContentIdentifiers do
  use Ecto.Migration
  import Ecto.Query

  # Logger.configure(level: :error)

  def change do
    create table(:content_identifiers) do
      add(:entry_id, :id)
      add(:schema, :string)
      add(:title, :text)
      add(:status, :integer)
      add(:language, :string)
      add(:cover, :string)
      add(:updated_at, :utc_datetime)
    end

    create(unique_index(:content_identifiers, [:entry_id, :schema]))

    flush()

    Application.load(:cachex)
    Application.ensure_all_started(:cachex)
    Cachex.start_link(name: :cache)
    Application.load(:gettext)
    Application.ensure_all_started(:gettext)
    Brando.Cache.Identity.set()
    Brando.Cache.SEO.set()
    Brando.Cache.Globals.set()

    # find all schemas with :entries

    blueprints = Brando.Blueprint.list_blueprints() ++ [Brando.Pages.Page, Brando.Pages.Fragment]

    for blueprint <- blueprints do
      # ensure it has identifier/1 and a db schema
      if {:__identifier_fields__, 0} in blueprint.__info__(:functions) &&
           blueprint.__schema__(:source) do
        fields = blueprint.__identifier_fields__

        fields =
          if blueprint.has_trait(Brando.Trait.Translatable) do
            fields ++ [:language]
          else
            fields
          end

        fields =
          if blueprint.has_trait(Brando.Trait.Status) do
            fields ++ [:status]
          else
            fields
          end

        assets = Enum.map(blueprint.__assets__, & &1.name)

        base_query =
          from(t in blueprint.__schema__(:source),
            select: %{id: t.id}
          )

        query =
          Enum.reduce(assets, base_query, fn asset, updated_query ->
            asset_id = :"#{to_string(asset)}_id"

            d_on = dynamic([t, {^asset, tbl2}], field(t, ^asset_id) == field(tbl2, :id))

            from(t in updated_query,
              left_join: b in Brando.Images.Image,
              as: ^asset,
              on: ^d_on
            )
          end)

        joins =
          assets
          |> Enum.map(fn asset -> {asset, dynamic([{^asset, tbl2}], tbl2)} end)
          |> Enum.into(%{})

        {fields, preload_fields} =
          Enum.reduce(fields, {[], []}, fn
            [{j, field}], {f_acc, j_acc} ->
              {[{j, [field]} | f_acc], [j | j_acc]}

            f, {f_acc, j_acc} ->
              {[f | f_acc], j_acc}
          end)

        query =
          Enum.reduce(preload_fields, query, fn preload_field, updated_query ->
            preload_field_id = :"#{to_string(preload_field)}_id"

            d_on =
              dynamic(
                [t, {^preload_field, tbl2}],
                field(t, ^preload_field_id) == field(tbl2, :id)
              )

            {:assoc, assoc} = blueprint.__changeset__() |> Map.get(preload_field)
            mod = assoc.queryable

            from(t in updated_query,
              left_join: b in ^mod,
              as: ^preload_field,
              on: ^d_on
            )
          end)

        preloads =
          preload_fields
          |> Enum.map(fn preload -> {preload, dynamic([{^preload, tbl2}], tbl2)} end)
          |> Enum.into(%{})

        query =
          from(t in query,
            select_merge: map(t, ^fields),
            select_merge: ^joins,
            select_merge: ^preloads
          )

        query =
          if Map.has_key?(blueprint.__changeset__(), :updated_at) do
            from(t in query,
              select_merge: %{updated_at: t.updated_at}
            )
          else
            query
          end

        entries = Brando.repo().all(query)

        for entry <- entries do
          identifier = blueprint.__identifier__(entry)
          Brando.repo().insert!(identifier)
        end
      end
    end
  end
end
