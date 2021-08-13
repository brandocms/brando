defmodule Brando.Blueprint.Relations do
  @moduledoc """
  WIP

  ## Many to many

  If you want to pass just ids of your many_to_many relation use `cast: true`
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
        %{type: :many_to_many, name: name, opts: %{cast: true, module: module}},
        changeset,
        _user
      ) do
    case Map.get(changeset.params, to_string(name)) do
      "" -> put_assoc(changeset, name, [])
      _ -> cast_collection(changeset, name, Brando.repo(), module)
    end
  end

  ##
  ## has_many
  def run_cast_relation(
        %{type: :has_many, name: name, opts: %{cast: true, module: _module} = opts},
        changeset,
        _user
      ) do
    required = Map.get(opts, :required, false)
    opts = Map.put(opts, :required, required)

    case Map.get(changeset.params, to_string(name)) do
      "" -> put_assoc(changeset, name, [])
      _ -> cast_assoc(changeset, name, to_changeset_opts(:has_many, opts))
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
    case Map.get(changeset.params, to_string(name)) do
      "" -> put_embed(changeset, name, [])
      _ -> cast_embed(changeset, name, to_changeset_opts(:embeds_many, opts))
    end
  end

  ##
  ## catch all for non casted relations
  def run_cast_relation(_, changeset, _user), do: changeset
end
