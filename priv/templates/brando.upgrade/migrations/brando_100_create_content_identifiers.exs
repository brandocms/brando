defmodule Brando.Repo.Migrations.CreateContentIdentifiers do
  use Ecto.Migration
  alias Brando.Content.Identifier
  import Ecto.Query

  def change do
    create table(:content_identifiers) do
      add :entry_id, :id
      add :schema, :string
      add :title, :string
      add :status, :integer
      add :language, :string
      add :cover, :string
      add :updated_at, :utc_datetime
    end

    create unique_index(:content_identifiers, [:entry_id, :schema])

    flush()

    Application.load(:cachex)
    Application.ensure_all_started(:cachex)
    Cachex.start_link(name: :cache)
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
        all_fields = fields ++ assets

        base_query =
          from(t in blueprint.__schema__(:source))

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

        query =
          from(t in query,
            select: %{
              id: t.id,
              updated_at: t.updated_at
            },
            select_merge: map(t, ^fields),
            select_merge: ^joins
          )

        entries = Brando.repo().all(query)

        for entry <- entries do
          identifier = blueprint.__identifier__(entry)
          user = Brando.repo().insert!(identifier)
        end
      end
    end
  end
end
