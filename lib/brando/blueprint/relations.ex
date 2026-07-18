defmodule Brando.Blueprint.Relations do
  @moduledoc """
  Runtime casting and metadata access for Blueprint relations.

  Relation declarations are compiled into Ecto associations by the Blueprint
  DSL. This module applies their casting options consistently when a generated
  changeset runs, including the empty-value contract used by collection form
  controls.

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
              default: &__MODULE__.default_client/2,
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

      def default_client(_entry, image) do
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
        through: [:article_contributors, :contributor]

  This enables us to use other fields from the join table, such as `sequence` in the example above.

  We can then use a multi select to select contributors for our article:

      input :article_contributors, :multi_select,
        options: &__MODULE__.get_contributors/2,
        relation_key: :contributor_id,
        resetable: true,
        label: t("Contributors")
  """

  import Brando.Blueprint.Utils
  import Ecto.Changeset
  import Ecto.Query

  alias Brando.Blueprint.Relations.Relation
  alias Ecto.Changeset
  alias Spark.Dsl.Extension

  @doc """
  Returns the compiled relation declarations for `module`.
  """
  @spec __relations__(module()) :: [Relation.t()]
  def __relations__(module) do
    Extension.get_entities(module, [:relations])
  end

  @doc """
  Returns the compiled relation named `name` for `module`.
  """
  @spec __relation__(module(), atom()) :: Relation.t() | nil
  def __relation__(module, name) do
    Extension.get_persisted(module, {:relation, name})
  end

  @doc """
  Returns the options for the compiled relation named `name`.
  """
  @spec __relation_opts__(module(), atom()) :: map() | keyword()
  def __relation_opts__(module, name) do
    case __relation__(module, name) do
      nil -> []
      relation -> Map.get(relation, :opts, [])
    end
  end

  @doc """
  Casts every relation declaration into `changeset` in declaration order.
  """
  @spec run_cast_relations(Changeset.t(), [Relation.t()], term()) :: Changeset.t()
  def run_cast_relations(changeset, relations, user) do
    Enum.reduce(relations, changeset, fn rel, cs -> run_cast_relation(rel, cs, user) end)
  end

  @doc """
  Applies one compiled relation's casting contract to `changeset`.

  Relations without casting enabled leave the changeset unchanged. Empty
  `has_many`, `many_to_many`, and `entries` values clear optional associations
  and add a required error for associations declared with `required: true`.
  """
  @spec run_cast_relation(Relation.t() | map(), Changeset.t(), term()) :: Changeset.t()

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
          [with: fn related_changeset, params -> apply(with_mod, with_fun, [related_changeset, params]) end]
      end

    merged_opts = Keyword.merge(to_changeset_opts(:belongs_to, opts), with_opts)
    cast_assoc(changeset, name, merged_opts)
  end

  ##
  ## many_to_many
  def run_cast_relation(%{type: :many_to_many, name: name, opts: %{cast: true, module: module} = opts}, changeset, _user) do
    if empty_collection_param?(relation_param(changeset, name)) do
      clear_or_require_assoc(changeset, name, opts)
    else
      Brando.M2M.cast_collection(
        changeset,
        name,
        fn ids ->
          Brando.Repo.all(from m in module, where: m.id in ^ids)
        end,
        Map.get(opts, :required, false),
        to_changeset_opts(:many_to_many, opts)
      )
    end
  end

  ##
  ## has_many
  def run_cast_relation(%{type: :has_many, name: name, opts: %{cast: true, module: module} = opts}, changeset, user) do
    required = Map.get(opts, :required, false)
    opts = Map.put(opts, :required, required)

    if empty_collection_param?(relation_param(changeset, name)) do
      clear_or_require_assoc(changeset, name, opts)
    else
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
    case relation_param(changeset, name) do
      {:ok, ""} ->
        if Map.get(opts, :required) do
          add_error(
            changeset,
            name,
            Map.get(opts, :required_message, "can't be blank"),
            validation: :required
          )
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
    case relation_param(changeset, name) do
      {:ok, ""} ->
        if Map.get(opts, :required) do
          cast_embed(changeset, name, to_changeset_opts(:embeds_many, opts))
        else
          put_embed(changeset, name, [])
        end

      _ ->
        cast_embed(changeset, name, to_changeset_opts(:embeds_many, opts))
    end
  end

  ##
  ## entries
  def run_cast_relation(%{type: :entries, name: name, opts: %{module: module} = opts}, changeset, user) do
    required = Map.get(opts, :required, false)
    opts = Map.put(opts, :required, required)

    if empty_collection_param?(relation_param(changeset, name)) do
      clear_or_require_assoc(changeset, name, opts)
    else
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

  defp relation_param(%{params: params}, name) when is_map(params) do
    string_name = to_string(name)

    cond do
      Map.has_key?(params, string_name) -> {:ok, Map.get(params, string_name)}
      Map.has_key?(params, name) -> {:ok, Map.get(params, name)}
      true -> :error
    end
  end

  defp relation_param(_changeset, _name), do: :error

  defp empty_collection_param?({:ok, value}) when value in [nil, "", []], do: true
  defp empty_collection_param?({:ok, value}) when is_map(value), do: map_size(value) == 0

  defp empty_collection_param?({:ok, value}) when is_list(value) do
    Enum.all?(value, &(&1 in [nil, ""]))
  end

  defp empty_collection_param?(_param), do: false

  defp clear_or_require_assoc(changeset, name, opts) do
    if Map.get(opts, :required, false) do
      add_error(
        changeset,
        name,
        Map.get(opts, :required_message, "can't be blank"),
        validation: :required
      )
    else
      put_assoc(changeset, name, [])
    end
  end

  @doc """
  Returns the association preloads derived from `schema`'s relations.
  """
  @spec preloads_for(module()) :: list()
  def preloads_for(schema) do
    relation_preloads = Module.concat(["Brando", "Blueprint", "RelationPreloads"])
    relation_preloads.for_schema(schema)
  end
end
