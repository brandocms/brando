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
          form_query &__MODULE__.query_with_preloads/1
          fieldset size: :full do
            inputs_for :clients,
              label: t("Clients"),
              cardinality: :many,
              style: {:transformer, :cover},
              inputs_for :clients,
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
        through: [:article_contributors, :contributor]

  This enables us to use other fields from the join table, such as `sequence` in the example above.

  We can then use a multi select to select contributors for our article:

      input :article_contributors, :multi_select,
        options: &__MODULE__.get_contributors/2,
        relation_key: :contributor_id,
        resetable: true,
        label: t("Contributors")
  """

  import Ecto.Changeset
  import Ecto.Query
  import Brando.M2M
  import Brando.Blueprint.Utils
  alias Brando.Exception
  alias Brando.Blueprint.Relation

  def build_relation(caller, name, type, opts \\ [])

  def build_relation(caller, name, :entries, opts) do
    join_module =
      Module.concat([
        caller,
        "#{Phoenix.Naming.camelize(to_string(name))}Identifier"
      ])

    opts = Keyword.put(opts, :module, join_module)
    %Relation{name: name, type: :entries, opts: Enum.into(opts, %{})}
  end

  def build_relation(_caller, name, type, opts) do
    %Relation{name: name, type: type, opts: Enum.into(opts, %{})}
  end

  defmacro relations(do: block) do
    relations(__CALLER__, block)
  end

  defp relations(_caller, block) do
    quote location: :keep do
      Module.put_attribute(__MODULE__, :brando_macro_context, :relations)
      Module.register_attribute(__MODULE__, :relations, accumulate: true)
      unquote(block)
    end
  end

  defmacro relation(name, type, opts \\ []) do
    opts = expand_literals(opts, __CALLER__)

    if type == :many_to_many do
      raise Exception.BlueprintError,
        message: """
        Many to many relations are deprecated.

            relation #{inspect(name)}, :many_to_many, ...

        Use two `:has_many` relations instead, with one being a `:through` assoc:

            relation :article_contributors, :has_many,
              module: Articles.ArticleContributor,
              preload_order: [asc: :sequence],
              on_replace: :delete,
              cast: true

            relation :contributors, :has_many,
              module: Articles.Contributor,
              through: [:article_contributors, :contributor]

        We can then set up a multi select for this relation:

            # in a form:
            input :article_contributors, :multi_select,
              options: &__MODULE__.get_contributors/2,
              relation_key: :contributor_id,
              resetable: true,
              label: t("Contributors")

        """
    end

    relation(__CALLER__.module, name, type, opts)
  end

  defp relation(caller, name, type, opts) do
    quote location: :keep do
      rel =
        build_relation(
          unquote(caller),
          unquote(name),
          unquote(type),
          unquote(opts)
        )

      Module.put_attribute(__MODULE__, :relations, rel)
    end
  end

  def run_cast_relations(changeset, relations, user) do
    Enum.reduce(relations, changeset, fn rel, cs -> run_cast_relation(rel, cs, user) end)
  end

  ##
  ## belongs_to

  def run_cast_relation(
        %{type: :belongs_to, name: name, opts: %{cast: true, module: _module} = opts},
        changeset,
        _user
      ) do
    cast_assoc(changeset, name, to_changeset_opts(:belongs_to, opts))
  end

  def run_cast_relation(
        %{type: :belongs_to, name: name, opts: %{cast: :with_user, module: module} = opts},
        changeset,
        user
      ) do
    with_opts = [with: {module, :changeset, [user]}]
    merged_opts = Keyword.merge(to_changeset_opts(:belongs_to, opts), with_opts)

    cast_assoc(changeset, name, merged_opts)
  end

  def run_cast_relation(
        %{type: :belongs_to, name: name, opts: %{cast: cast_opts} = opts},
        changeset,
        user
      ) do
    with_opts =
      case Keyword.get(cast_opts, :with) do
        {with_mod, with_fun, with_user: true} ->
          [with: {with_mod, with_fun, [user]}]

        {with_mod, with_fun} ->
          cast_assoc(changeset, name, with: {with_mod, with_fun, []})
      end

    merged_opts = Keyword.merge(to_changeset_opts(:belongs_to, opts), with_opts)
    cast_assoc(changeset, name, merged_opts)
  end

  ##
  ## many_to_many
  def run_cast_relation(
        %{type: :many_to_many, name: name, opts: %{cast: true, module: module} = opts},
        changeset,
        _user
      ) do
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
            Brando.repo().all(from m in module, where: m.id in ^ids)
          end,
          Map.get(opts, :required, false)
        )
    end
  end

  ##
  ## has_many
  def run_cast_relation(
        %{type: :has_many, name: name, opts: %{cast: true, module: module} = opts},
        changeset,
        user
      ) do
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
            [with: &module.changeset(&1, &2, user), drop_param: :drop_ids, sort_param: :sort_ids]
        )
    end
  end

  ##
  ## embeds_one
  def run_cast_relation(
        %{type: :embeds_one, name: name, opts: opts},
        changeset,
        _user
      ) do
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
  def run_cast_relation(
        %{type: :embeds_many, name: name, opts: opts},
        changeset,
        _user
      ) do
    case Map.get(changeset.params, to_string(name)) do
      "" ->
        if Map.get(opts, :required) do
          cast_embed(changeset, name, to_changeset_opts(:embeds_many, opts))
        else
          put_embed(changeset, name, [])
        end

      _ ->
        updated_opts = to_changeset_opts(:embeds_many, opts)
        require Logger

        Logger.error("""

        => #{inspect(name)}
        => #{inspect(updated_opts, pretty: true)}

        """)

        cast_embed(changeset, name, updated_opts)
    end
  end

  ##
  ## entries
  def run_cast_relation(
        %{type: :entries, name: name, opts: %{module: module} = opts},
        changeset,
        _user
      ) do
    required = Map.get(opts, :required, false)
    opts = Map.put(opts, :required, required)

    case Map.get(changeset.params, "#{to_string(name)}_identifiers") do
      "" ->
        put_assoc(changeset, :"#{name}_identifiers", [])

      _ ->
        cast_assoc(
          changeset,
          :"#{name}_identifiers",
          to_changeset_opts(:has_many, opts) ++
            [
              with: &module.changeset/3,
              sort_param: :"#{to_string(name)}_sequence",
              drop_param: :"#{to_string(name)}_delete"
            ]
        )
    end
  end

  ##
  ## catch all for non casted relations
  def run_cast_relation(_, changeset, _user), do: changeset

  def preloads_for(schema) do
    schema.__relations__()
    |> Enum.filter(&(&1.type in [:belongs_to, :has_many, :many_to_many] and &1.name != :creator))
    |> Enum.map(fn
      %{type: :has_many, name: name, opts: %{cast: true, module: mod}} ->
        sub_assets = Enum.map(mod.__assets__(), & &1.name)

        if mod.has_trait(Brando.Trait.Sequenced) do
          preload_query = from q in mod, order_by: [asc: q.sequence], preload: ^sub_assets
          {name, preload_query}
        else
          (sub_assets == [] && name) || {name, sub_assets}
        end

      %{name: name} ->
        name
    end)
  end

  defp expand_literals(ast, env) do
    if Macro.quoted_literal?(ast) do
      Macro.prewalk(ast, &expand_alias(&1, env))
    else
      ast
    end
  end

  defp expand_alias({:__aliases__, _, _} = alias, env),
    do: Macro.expand(alias, %{env | function: {:relation, 3}})

  defp expand_alias(other, _env), do: other

  # defp expand_nested_module_alias({:__aliases__, _, [Elixir, _ | _] = alias}, _env),
  #   do: Module.concat(alias)

  # defp expand_nested_module_alias({:__aliases__, _, [h | t]}, env) when is_atom(h),
  #   do: Module.concat([env.module, h | t])

  # defp expand_nested_module_alias(other, _env), do: other
end
