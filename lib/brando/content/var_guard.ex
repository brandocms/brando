defmodule Brando.Content.VarGuard do
  @moduledoc """
  What a save may change in a var beyond its value. A var's type decides how
  its value is protected when it prints, so it comes from the definition,
  never from the request.

  On a block's vars and table rows (`Brando.Content.Block.block_changeset/3`
  and `recursive_block_changeset/4`), so every write that casts blocks gets it:

    * a saved var keeps its stored type, key and options.
    * a new var takes its type and options from the definition of its key: the
      block's module for a block var, the module's table template for a row
      var. A new var whose key has no definition is left out.
    * a value is checked against the type and options that result (`Brando.Color`,
      `Brando.Content.Var.ValidateValue`).

  These are put back rather than refused, as `Brando.Content.RefGuard` does for
  refs, since only a crafted request or a stale view sends them. An invalid
  value is refused.

  A module save (`Brando.Content.Blocks.sync_module/2`) and resolving a stale
  block (`Brando.Content.StaleBlocks`) retype vars on the server, without
  casting. So does a superuser moving a saved block to another module
  (`follow_module/1`).

  On the Globals screen, `global_values/2` lets through values only.
  """
  alias Brando.Content.Proposals
  alias Ecto.Changeset

  # What the Globals screen fills in. The rest of a global is its definition.
  @value_params ~w(id value value_boolean image_id file_id video_id gallery_id form_id palette_id identifier_id
                   link_text link_type link_target_blank)

  @doc """
  The definitions new vars of the block changeset `changeset` are held to, by
  key: `vars` for the block's, `rows` for its table rows'. Read only when the
  params hold a new var.
  """
  @spec definitions(Changeset.t()) :: %{vars: map(), rows: map()}
  def definitions(%Changeset{params: params, data: block} = changeset) do
    new_vars? = new_var?(params["vars"], loaded(block, :vars))
    saved_cells = block |> loaded(:table_rows) |> Enum.flat_map(&loaded(&1, :vars))
    new_cells? = params["table_rows"] |> rows() |> Enum.any?(&new_var?(param(&1, "vars"), saved_cells))

    if new_vars? or new_cells? do
      module = module(changeset)

      %{
        vars: by_key((new_vars? && module && module.vars) || []),
        rows: by_key((new_cells? && module && Proposals.table_vars(module)) || [])
      }
    else
      %{vars: %{}, rows: %{}}
    end
  end

  @doc """
  `var` as it may be cast from `attrs`, and the fields to leave out of the cast.

  A saved var keeps its type, key and options. A new var starts from the
  definition of its key in `definitions` (type, options and default value, so
  a default is not taken for a value an editor sent), or is `:refused` without
  one. With `definitions` `nil`, for a caller that has none to give, a new var
  is cast as it comes.
  """
  @spec hold(term(), map(), map() | nil) :: {term(), [atom()]} | :refused
  def hold(var, attrs, definitions) do
    cond do
      saved?(var) ->
        {var, [:type, :key, :options]}

      is_nil(definitions) ->
        {var, []}

      definition = Map.get(definitions, to_string_or_nil(param(attrs, "key"))) ->
        {seed(var, definition), [:type, :options]}

      true ->
        :refused
    end
  end

  defp seed(%Changeset{} = changeset, definition), do: %{changeset | data: seed(changeset.data, definition)}

  defp seed(%{} = var, definition),
    do: %{var | type: definition.type, options: definition.options || [], value: definition.value}

  @doc """
  `changeset` without the params of its `held` fields: a form reads a field's
  params when it has no change, and would show what was sent, not what is held.
  """
  @spec forget_params(Changeset.t(), [atom()]) :: Changeset.t()
  def forget_params(%Changeset{params: params} = changeset, held) when is_map(params),
    do: %{changeset | params: Map.drop(params, Enum.map(held, &Atom.to_string/1))}

  def forget_params(changeset, _held), do: changeset

  @doc "Takes the vars `hold/3` refused out of `changeset`'s `relation`."
  @spec drop_refused(Changeset.t(), atom()) :: Changeset.t()
  def drop_refused(%Changeset{changes: changes} = changeset, relation) do
    case changes do
      %{^relation => vars} when is_list(vars) ->
        %{changeset | changes: Map.put(changes, relation, Enum.reject(vars, &(&1.action == :ignore)))}

      _ ->
        changeset
    end
  end

  @doc """
  The block changeset `changeset` with its saved vars following a module change
  (`Brando.Content.RefGuard.module_changed?/1`): a var the new module defines as
  another type takes that type and its options, and starts empty, since its
  value was not checked for that type. A var it does not define stays dormant.
  """
  @spec follow_module(Changeset.t()) :: Changeset.t()
  def follow_module(%Changeset{} = changeset) do
    if Brando.Content.RefGuard.module_changed?(changeset), do: retype_saved_vars(changeset), else: changeset
  end

  defp retype_saved_vars(%Changeset{data: block} = changeset) do
    %{vars: saved} = Brando.Repo.preload(block, :vars)
    definitions = by_key((module(changeset) || %{vars: []}).vars)
    cast = Map.get(changeset.changes, :vars, [])
    cast_ids = MapSet.new(cast, & &1.data.id)
    unmentioned = saved |> Enum.reject(&MapSet.member?(cast_ids, &1.id)) |> Enum.map(&%{Changeset.change(&1) | action: :update})
    vars = Enum.map(cast ++ unmentioned, &retype(&1, definitions))

    %{changeset | changes: Map.put(changeset.changes, :vars, vars)}
  end

  defp retype(%Changeset{action: action} = var, _definitions) when action in [:replace, :delete], do: var

  defp retype(%Changeset{} = var, definitions) do
    definition = Map.get(definitions, Changeset.get_field(var, :key))
    type = Changeset.get_field(var, :type)

    if saved?(var) and definition && definition.type != type do
      var
      |> Changeset.put_change(:type, definition.type)
      |> Changeset.put_embed(:options, definition.options || [])
      |> Changeset.force_change(:value, nil)
      |> Map.update!(:errors, &Keyword.delete(&1, :value))
      |> then(&%{&1 | valid?: &1.errors == []})
    else
      var
    end
  end

  @doc """
  The params of a save on the Globals screen, which fills in values: the set
  `global_set` as it is, its vars with their values from `params`. A var the
  params leave out stays, and one the set does not have is left out.
  """
  @spec global_values(map(), map()) :: map()
  def global_values(%{vars: vars} = global_set, params) do
    rows = params["vars"] |> rows() |> Map.new(&{to_string(param(&1, "id")), &1})

    values =
      vars
      |> Enum.with_index()
      |> Map.new(fn {var, index} ->
        row = rows |> Map.get(to_string(var.id), %{}) |> Map.take(@value_params) |> Map.put("id", var.id)
        {to_string(index), row}
      end)

    base = %{"id" => global_set.id}
    if Map.has_key?(params, "vars"), do: Map.put(base, "vars", values), else: base
  end

  defp module(changeset) do
    case Changeset.get_field(changeset, :module_id) do
      nil -> nil
      id -> Brando.Content.fetch_module(id, Changeset.get_field(changeset, :module_origin) || :local)
    end
  end

  defp by_key(vars), do: Map.new(vars, &{&1.key, &1})

  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(value), do: to_string(value)

  defp saved?(%Changeset{data: data}), do: saved?(data)
  defp saved?(%{id: id}), do: not is_nil(id)
  defp saved?(_var), do: false

  # An id the owner does not have (a restored revision's row, since deleted)
  # is a new row as well.
  defp new_var?(vars, saved) do
    ids = MapSet.new(saved, &to_string(&1.id))
    vars |> rows() |> Enum.any?(&(not MapSet.member?(ids, to_string(param(&1, "id")))))
  end

  defp loaded(owner, relation) do
    case Map.get(owner, relation) do
      rows when is_list(rows) -> rows
      _ -> []
    end
  end

  defp rows(%{} = rows) when not is_struct(rows), do: Map.values(rows)
  defp rows(rows) when is_list(rows), do: rows
  defp rows(_rows), do: []

  defp param(%{} = row, key), do: Map.get(row, key, Map.get(row, String.to_existing_atom(key)))
  defp param(_row, _key), do: nil
end
