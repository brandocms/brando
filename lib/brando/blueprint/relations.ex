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

  def run_embed_attributes(changeset, attributes, user, module) do
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
    # TODO: Find a way to differentiate a deleted embed from an updated/created embed.
    # - If it is a deleted embed, we can `put_embed(changeset, name, nil)`
    # - If it is an upserted embed, we can `cast_embed(changeset, name ...
    require Logger

    Logger.error(
      "-- pre  cast_embed -> #{inspect(name)}: #{inspect(Map.get(changeset.changes, name), pretty: true)}"
    )

    Logger.error(inspect(changeset.params, pretty: true))
    we = cast_embed(changeset, name, to_changeset_opts(:embeds_one, opts))

    Logger.error(
      "-- post cast_embed -> #{inspect(name)}: #{inspect(Map.get(we.changes, name), pretty: true)}"
    )

    we
  end

  ##
  ## embeds_many
  def run_cast_relation(
        %{type: :embeds_many, name: name, opts: opts},
        changeset,
        _user
      ) do
    cast_embed(changeset, name, to_changeset_opts(:embeds_many, opts))
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
