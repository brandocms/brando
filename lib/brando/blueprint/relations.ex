defmodule Brando.Blueprint.Relations do
  @moduledoc """
  WIP

  ## Has many

  ### Example

      relations do
        relation :clients, :has_many, module: Client, cast: true, on_replace: :delete
      end

      forms do
        form do
          query &__MODULE__.query_with_preloads/1
          fieldset do
            size :full
            inputs_for :clients,
              label: t("Clients"),
              cardinality: :many,
              style: {:transformer, :cover},
              default: &__MODULE__.default_client/1,
              listing: &__MODULE__.client_listing/1 do
              input :cover, :image, label: t("Cover", Client)
              input :name, :text, placeholder: "Client Name"
              input :description, :rich_text
            end
          end
        end
      end

      def query_with_preloads(id) do
        %{matches: %{id: id}, preload: [clients: :cover]}
      end

      def default_client(image) do
        %Client{
          name: Brando.Images.get_image_orientation(image)
        }
      end

      def client_listing(assigns) do
        ~H\"""
        <div>
          <%= @entry.name %><br>
          <strong>Some classification</strong>
          <div class="tags flex-h justify-start gap-1 mt-1">
            <div class="badge">
              Monochrome
            </div>
            <div class="badge">
              Vertical
            </div>
            <div class="badge">
              Outdoors
            </div>
          </div>
        </div>
        \"""
      end


  ## Many to many

  Instead of using a many to many association, we use two has_many associations

      relation :article_contributors, :has_many,
        module: Articles.ArticleContributor,
        preload_order: [asc: :sequence],
        on_replace: :delete_if_exists,
        cast: true

      relation :contributors, :has_many,
        module: Articles.Contributor,
        through: [:article_contributors, :contributor],
        preload_order: [asc: :sequence]

  This enables us to use other fields from the join table, such as `sequence` in the example above.

  We can then use a multi select to select contributors for our article:

      input :article_contributors, :multi_select,
        options: &__MODULE__.get_contributors/2,
        relation_key: :contributor_id,
        resetable: true,
        label: t("Contributors")
  """

  import Brando.Blueprint.Utils
  import Brando.M2M
  import Ecto.Changeset
  import Ecto.Query

  alias Brando.Blueprint.Relations
  alias Spark.Dsl.Extension

  def __relations__(module) do
    Extension.get_entities(module, [:relations])
  end

  def __relation__(module, name) do
    Extension.get_persisted(module, name)
  end

  def __relation_opts__(module, name) do
    module
    |> __relation__(name)
    |> Map.get(:opts, [])
  end

  def run_cast_relations(changeset, relations, user) do
    Enum.reduce(relations, changeset, fn rel, cs -> run_cast_relation(rel, cs, user) end)
  end

  ##
  ## has_one

  def run_cast_relation(%{type: :has_one, name: name, opts: %{cast: true, module: module} = opts}, changeset, user) do
    with_opts = [with: &module.changeset(&1, &2, user)]
    merged_opts = Keyword.merge(to_changeset_opts(:has_one, opts), with_opts)

    cast_assoc(changeset, name, merged_opts)
  end

  ##
  ## belongs_to

  def run_cast_relation(%{type: :belongs_to, name: name, opts: %{cast: true, module: _module} = opts}, changeset, _user) do
    cast_assoc(changeset, name, to_changeset_opts(:belongs_to, opts))
  end

  def run_cast_relation(
        %{type: :belongs_to, name: name, opts: %{cast: :with_user, module: module} = opts},
        changeset,
        user
      ) do
    with_opts = [with: &module.changeset(&1, &2, user)]
    merged_opts = Keyword.merge(to_changeset_opts(:belongs_to, opts), with_opts)

    cast_assoc(changeset, name, merged_opts)
  end

  def run_cast_relation(%{type: :belongs_to, name: name, opts: %{cast: cast_opts} = opts}, changeset, user) do
    with_opts =
      case Keyword.get(cast_opts, :with) do
        {with_mod, with_fun, with_user: true} ->
          [with: fn changeset, params -> apply(with_mod, with_fun, [changeset, params, user]) end]

        {with_mod, with_fun} ->
          cast_assoc(changeset, name, with: {with_mod, with_fun, []})
      end

    merged_opts = Keyword.merge(to_changeset_opts(:belongs_to, opts), with_opts)
    cast_assoc(changeset, name, merged_opts)
  end

  ##
  ## many_to_many
  def run_cast_relation(%{type: :many_to_many, name: name, opts: %{cast: true, module: module} = opts}, changeset, _user) do
    case Map.get(changeset.params, to_string(name)) do
      "" ->
        if Map.get(opts, :required) do
          cast_assoc(changeset, name, required: true)
        else
          put_assoc(changeset, name, [])
        end

      _ ->
        cast_collection(
          changeset,
          name,
          fn ids ->
            Brando.Repo.all(from m in module, where: m.id in ^ids)
          end,
          Map.get(opts, :required, false)
        )
    end
  end

  ##
  ## has_many
  def run_cast_relation(%{type: :has_many, name: name, opts: %{cast: true, module: module} = opts}, changeset, user) do
    required = Map.get(opts, :required, false)
    opts = Map.put(opts, :required, required)

    case Map.get(changeset.params, to_string(name)) do
      "" ->
        put_assoc(changeset, name, [])

      _ ->
        opts = Map.put(opts, :with, &module.changeset(&1, &2, user, &3, []))

        cast_assoc(
          changeset,
          name,
          to_changeset_opts(:has_many, opts)
        )
    end
  end

  ##
  ## embeds_one
  def run_cast_relation(%{type: :embeds_one, name: name, opts: opts}, changeset, _user) do
    # A hack to remove an embeds_one, specifically an image
    case Map.get(changeset.params, to_string(name)) do
      "" ->
        if Map.get(opts, :required) do
          cast_embed(changeset, name, required: true)
        else
          put_embed(changeset, name, nil)
        end

      _ ->
        cast_embed(changeset, name, to_changeset_opts(:embeds_one, opts))
    end
  end

  ##
  ## embeds_many
  def run_cast_relation(%{type: :embeds_many, name: name, opts: opts}, changeset, _user) do
    case Map.get(changeset.params, to_string(name)) do
      "" ->
        if Map.get(opts, :required) do
          cast_embed(changeset, name, to_changeset_opts(:embeds_many, opts))
        else
          put_embed(changeset, name, [])
        end

      _ ->
        updated_opts = to_changeset_opts(:embeds_many, opts)
        cast_embed(changeset, name, updated_opts)
    end
  end

  ##
  ## entries
  def run_cast_relation(%{type: :entries, name: name, opts: %{module: module} = opts}, changeset, user) do
    required = Map.get(opts, :required, false)
    opts = Map.put(opts, :required, required)

    case Map.get(changeset.params, to_string(name)) do
      "" ->
        put_assoc(changeset, name, [])

      _ ->
        cast_assoc(
          changeset,
          name,
          to_changeset_opts(:has_many, opts) ++
            [
              with: &module.changeset(&1, &2, user, &3, []),
              sort_param: :"sort_#{to_string(name)}_ids",
              drop_param: :"drop_#{to_string(name)}_ids"
            ]
        )
    end
  end

  ##
  ## catch all for non casted relations
  def run_cast_relation(_, changeset, _user), do: changeset

  def preloads_for(schema) do
    schema
    |> Relations.__relations__()
    |> Enum.filter(
      &(&1.type in [:belongs_to, :has_many, :many_to_many] and &1.name != :creator and
          &1.opts.module != :blocks)
    )
    |> Enum.map(fn
      %{type: :has_many, name: name, opts: %{cast: true, module: mod}} ->
        sub_assets = Enum.map(Brando.Blueprint.Assets.__assets__(mod), & &1.name)

        # filter out sub_rels where the relation's module matches `schema`
        sub_rels =
          for rel <- Relations.__relations__(mod),
              rel.opts.module != schema,
              rel.type not in [:embeds_many, :embeds_one] do
            rel.name
          end

        sub_preloads = sub_assets ++ sub_rels

        if mod.has_trait(Brando.Trait.Sequenced) do
          preload_query = from q in mod, order_by: [asc: q.sequence], preload: ^sub_preloads
          {name, preload_query}
        else
          (sub_preloads == [] && name) || {name, sub_preloads}
        end

      %{name: name} ->
        name
    end)
  end
end
