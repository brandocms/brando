defmodule Brando.Blueprint.Relations do
  @moduledoc ~S|
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
          name: "Default! #{Brando.Images.get_image_orientation(image)}"
        }
      end

      def client_listing(assigns) do
        ~H"""
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
        """
      end


  ## Many to many

  If you want to pass just ids of your many_to_many relation use `cast: true`
  |

  import Ecto.Changeset
  import Ecto.Query
  import Brando.M2M
  import Brando.Blueprint.Utils
  alias Brando.Exception
  alias Brando.Blueprint.Relation

  def build_relation(name, type, opts \\ [])

  def build_relation(name, :image, opts) do
    %Relation{
      name: name,
      type: :embeds_one,
      opts: Map.merge(Enum.into(opts, %{}), %{module: Brando.Images.Image})
    }
  end

  def build_relation(name, type, opts) do
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
    if type == :many_to_many do
      raise Exception.BlueprintError,
        message: """
        Many to many relations are deprecated.

            relation #{inspect(name)}, :many_to_many, ...

        Use two `:has_many` relations instead, with one being a `:through` assoc:

            relation :article_contributors, :has_many,
              module: Articles.ArticleContributor,
              preload_order: [asc: :sequence],
              cast: true

            relation :contributors, :has_many,
              module: Articles.Contributor,
              through: [:article_contributors, :contributor]

        """
    end

    relation(__CALLER__, name, type, opts)
  end

  defp relation(_caller, name, type, opts) do
    quote location: :keep do
      rel =
        build_relation(
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
          to_changeset_opts(:has_many, opts) ++ [with: &module.changeset(&1, &2, user)]
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
        cast_embed(changeset, name, to_changeset_opts(:embeds_many, opts))
    end
  end

  ##
  ## embeds_many
  def run_cast_relation(
        %{type: :entries, name: name, opts: opts},
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
        cast_embed(changeset, name, to_changeset_opts(:embeds_many, opts))
    end
  end

  ##
  ## catch all for non casted relations
  def run_cast_relation(_, changeset, _user), do: changeset

  def load_relations(entry) do
    relations = get_all_relations(entry.__struct__)
    Brando.repo().preload(entry, relations)
  end

  def get_all_relations(schema) do
    image_preloads =
      schema.__assets__
      |> Enum.filter(&(&1.type == :image))
      |> Enum.map(& &1.name)

    gallery_preloads =
      schema.__assets__
      |> Enum.filter(&(&1.type == :gallery))
      |> Enum.map(&[{&1.name, [{:gallery_images, :image}]}])

    rel_preloads =
      schema.__relations__
      |> Enum.filter(&(&1.type == :belongs_to and &1.name != :creator))
      |> Enum.map(& &1.name)

    # TODO: Add alternate_entries here if Translatable?

    Enum.uniq(gallery_preloads ++ image_preloads ++ rel_preloads)
  end
end
