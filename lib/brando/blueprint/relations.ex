defmodule Brando.Blueprint.Relations do
  @moduledoc """
  WIP

  ## Many to many

  If you want to pass just ids of your many_to_many relation use `cast: :collection`
  """
  import Ecto.Changeset
  import Brando.M2M
  import Brando.Blueprint.Utils
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
      Module.register_attribute(__MODULE__, :relations, accumulate: true)
      unquote(block)
    end
  end

  defmacro relation(name, type, opts \\ []) do
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

  def run_embed_attributes(changeset, attributes, user, _module) do
    attributes
    |> Enum.filter(&(&1.type == :image))
    |> Enum.map(fn image ->
      Map.merge(image, %{type: :embeds_one, opts: %{module: Brando.Images.Image}})
    end)
    |> Enum.reduce(changeset, fn rel, cs ->
      run_cast_relation(rel, cs, user)
    end)
  end

  def run_cast_relations(changeset, relations, user) do
    # if we have images or video, add these here, since we should cast_embed them
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
        %{type: :many_to_many, name: name, opts: %{cast: :collection, module: module}},
        changeset,
        _user
      ) do
    cast_collection(changeset, name, Brando.repo(), module)
  end

  ##
  ## has_many
  def run_cast_relation(
        %{type: :has_many, name: name, opts: %{cast: true, module: _module} = opts},
        changeset,
        _user
      ) do
    cast_assoc(changeset, name, to_changeset_opts(:has_many, opts))
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
      "" -> put_embed(changeset, name, nil)
      _ -> cast_embed(changeset, name, to_changeset_opts(:embeds_one, opts))
    end
  end

  ##
  ## embeds_many
  def run_cast_relation(
        %{type: :embeds_many, name: name, opts: opts},
        changeset,
        _user
      ) do
    casted_changeset = cast_embed(changeset, name, to_changeset_opts(:embeds_many, opts))
    param = Map.get(changeset.params, to_string(name))
    field = Ecto.Changeset.get_field(casted_changeset, name)

    require Logger

    if name == :metas do
      Logger.error("==> embeds_many :metas")
      Logger.error(inspect(Map.get(casted_changeset.changes, :metas), pretty: true))
      Logger.error(inspect(Map.get(casted_changeset.params, "metas"), pretty: true))
      Logger.error(inspect(Keyword.get(casted_changeset.errors, :metas), pretty: true))
    end

    # if Map.get(casted_changeset.params, to_string(name)) == "null" do
    #   Logger.error("==> it is null, put_embed empty list")
    #   cs = Ecto.Changeset.delete_change(casted_changeset, name)
    #   # cs = put_embed(casted_changeset, name, [])
    #   # cs = %{cs | errors: Keyword.delete(cs.errors, name)}
    #   Logger.error(inspect(cs, pretty: true))
    #   cs
    # else
    #   casted_changeset
    # end

    casted_changeset

    # A hack to remove the last embeds_many in a list
    # if is_map(param) && Map.keys(param) == ["0"] &&
    #      get_in(param, ["0", "marked_as_deleted"]) == "true" do
    #   if field == [] do
    #     cs = put_embed(casted_changeset, name, nil)
    #     require Logger
    #     Logger.error("==> field == []")
    #     Logger.error(cs.changes, pretty: true)
    #     Logger.error(cs.errors, pretty: true)
    #     %{cs | errors: Keyword.delete(cs.errors, name)}
    #   else
    #     require Logger
    #     Logger.error("==> field != []")
    #     casted_changeset
    #   end
    # else
    #   casted_changeset
    # end
  end

  ##
  ## catch all for non casted relations
  def run_cast_relation(_, changeset, _user), do: changeset
end
