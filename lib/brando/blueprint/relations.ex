defmodule Brando.Blueprint.Relations do
  @moduledoc """
  WIP

  ## Many to many

  If you want to pass just ids of your many_to_many relation use `cast: :collection`
  """
  import Ecto.Changeset
  import Brando.M2M

  def build_relation(name, type, opts \\ []) do
    %{name: name, type: type, opts: Enum.into(opts, %{})}
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
    Enum.reduce(relations, changeset, fn rel, cs -> run_cast_relation(rel, cs, user) end)
  end

  ##
  ## belongs_to

  def run_cast_relation(
        %{type: :belongs_to, opts: %{cast: true, module: _module, name: name}},
        changeset,
        _user
      ) do
    cast_assoc(changeset, name)
  end

  def run_cast_relation(
        %{type: :belongs_to, opts: %{cast: :with_user, module: module, name: name}},
        changeset,
        user
      ) do
    cast_assoc(changeset, name, with: {module, :changeset, [user]})
  end

  def run_cast_relation(
        %{type: :belongs_to, opts: %{cast: cast_opts, name: name}},
        changeset,
        user
      ) do
    case Keyword.get(cast_opts, :with) do
      {with_mod, with_fun, with_user: true} ->
        cast_assoc(changeset, name, with: {with_mod, with_fun, [user]})

      {with_mod, with_fun} ->
        cast_assoc(changeset, name, with: {with_mod, with_fun, []})
    end
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
        %{type: :has_many, name: name, opts: %{cast: true, module: module}},
        changeset,
        _user
      ) do
    cast_assoc(changeset, name, module)
  end

  ##
  ## embeds_one
  def run_cast_relation(
        %{type: :embeds_one, name: name, opts: %{module: module}},
        changeset,
        _user
      ) do
    cast_embed(changeset, name, module)
  end

  ##
  ## embeds_many
  def run_cast_relation(
        %{type: :embeds_many, name: name, opts: %{module: module}},
        changeset,
        _user
      ) do
    cast_embed(changeset, name, module)
  end

  ##
  ## catch all for non casted relations
  def run_cast_relation(
        _,
        changeset,
        _user
      ) do
    changeset
  end
end
