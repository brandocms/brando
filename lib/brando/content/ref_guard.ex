defmodule Brando.Content.RefGuard do
  @moduledoc """
  What a block save may change in the block's refs, applied to the cast
  refs of a block changeset (`Brando.Content.Block.block_changeset/3` and
  `recursive_block_changeset/4`), so every write that casts blocks gets it:
  the block editor, recovery, drafts, content transfer and revisions.

  For everyone, a ref keeps the type its module gives it:

    * a saved ref's type only changes to one its module's definition of the
      ref allows: the same type, or, for a media slot, a type in its
      `available_blocks` (or back to `media`). Otherwise the saved data stays.
    * a new ref takes the module definition's data when its type is not one
      the definition allows. A new ref the module does not define keeps its
      type only when that type holds no markup, or when a superuser saves it.
    * a saved ref keeps its name when the module defines a ref of the new
      name with a type it does not allow.

  For anyone but a superuser (`Brando.Authorization.Boundary.superuser?/1`),
  the markup of an HTML ref (`text` and `params`), an SVG ref (`code` and
  `class`) and a media slot's SVG template (`template_svg`) stays what it
  was: a saved ref's own, or for a new ref the module definition's. A new ref
  may also carry markup a ref of the same name holds in a saved block of the
  same module, as a copied or pasted block does. Anything else is put back,
  and the editor's other changes, an HTML ref's `values` included, are kept.

  Changes are put back rather than refused. The editor never offers them, so
  only a crafted request or a stale view sends them; and a refused change
  would still sit in the editor's changeset, where live preview and the edit
  session pass it on to other editors before any save. Invalid `values` are
  refused: they render as nothing, so they can sit in a changeset safely.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.Boundary
  alias Brando.Content.Block
  alias Brando.Content.Ref
  alias Brando.Villain.Blocks
  alias Brando.Villain.Blocks.HtmlBlock
  alias Ecto.Changeset

  # The data fields that are markup, by ref type
  @markup %{"html" => [:text, :params], "svg" => [:code, :class], "media" => [:template_svg]}
  @markup_types Map.keys(@markup)

  @doc "The ref types whose data holds markup only a superuser changes."
  def markup_types, do: @markup_types

  @doc """
  The block changeset `changeset` with its cast refs held to what `user`
  may change.
  """
  @spec guard(Changeset.t(), term()) :: Changeset.t()
  def guard(%Changeset{changes: %{refs: [_ | _] = refs}} = changeset, user) do
    state = %{block: changeset, user: user, module: :unloaded, superuser: :unknown}
    {refs, _state} = Enum.map_reduce(refs, state, &guard_ref/2)

    changeset = %{changeset | changes: Map.put(changeset.changes, :refs, refs)}
    %{changeset | valid?: changeset.errors == [] and nested_valid?(changeset)}
  end

  def guard(changeset, _user), do: changeset

  defp guard_ref(%Changeset{action: action} = ref, state) when action in [:replace, :delete, :ignore],
    do: {ref, state}

  defp guard_ref(%Changeset{} = ref, state) do
    old = ref.data.data
    new = ref |> Changeset.get_field(:data) |> applied()
    {ref, state} = guard_name(ref, new, state)

    cond do
      is_nil(new) ->
        {ref, state}

      not is_nil(old) and type(old) == type(new) ->
        guard_markup(ref, old, new, old, state)

      true ->
        guard_type(ref, old, new, state)
    end
  end

  defp guard_ref(ref, state), do: {ref, state}

  # A saved ref takes a new name only when the module defines no ref of that
  # name of another type: otherwise it would take that ref's place in the
  # template. A name the module does not define (a revision restored after a
  # rename gives one back) renders nowhere.
  defp guard_name(%Changeset{data: %{id: id}, changes: %{name: name}} = ref, new, state) when not is_nil(id) do
    {definition, state} = definition(state, name)

    if definition && not type_allowed?(definition, type(new)),
      do: {Changeset.delete_change(ref, :name), state},
      else: {ref, state}
  end

  defp guard_name(ref, _new, state), do: {ref, state}

  # A changed type, or a new ref
  defp guard_type(ref, old, new, state) do
    {definition, state} = definition(state, Changeset.get_field(ref, :name))

    cond do
      definition && type_allowed?(definition, type(new)) ->
        guard_markup(ref, old, new, markup_source(old, new, definition), state)

      old ->
        {put_data(ref, old), state}

      definition ->
        {put_data(ref, definition.data), state}

      true ->
        guard_undefined(ref, new, state)
    end
  end

  # A media slot that became an SVG takes its own SVG template
  defp markup_source(old, new, definition) do
    if type(old) == "media" and type(new) == "svg", do: old, else: definition
  end

  # A new ref the module does not define
  defp guard_undefined(ref, new, state) do
    if type(new) in @markup_types do
      {state, superuser?} = superuser?(state)
      if superuser?, do: {ref, state}, else: {%{ref | action: :ignore}, state}
    else
      {ref, state}
    end
  end

  defp type_allowed?(%{data: %{type: type}}, type), do: true

  defp type_allowed?(%{data: %{type: "media", data: data}}, type) do
    available = Map.get(data || %{}, :available_blocks) || []
    type in available and Blocks.ref_types_compatible?(Blocks.MediaBlock, block_module(type))
  end

  defp type_allowed?(_definition, _type), do: false

  defp block_module(type) do
    Keyword.get(Blocks.list_blocks(), String.to_existing_atom(type))
  rescue
    ArgumentError -> nil
  end

  # `source` is where the ref's markup may come from: the saved ref or its
  # module definition.
  defp guard_markup(ref, old, new, source, state) do
    type = type(new)

    allowed = if type in @markup_types, do: markup(type, baseline(type, source))

    if is_nil(allowed) or comparable(type, markup(type, new.data)) == comparable(type, allowed),
      do: {ref, state},
      else: guard_changed_markup(ref, old, new, allowed, state)
  end

  defp guard_changed_markup(ref, old, new, allowed, state) do
    {state, superuser?} = superuser?(state)

    cond do
      superuser? -> {ref, state}
      is_nil(old) and stored?(state, ref, type(new), new.data) -> {ref, state}
      true -> {restore(ref, new, allowed), state}
    end
  end

  # The data the markup is held to: the source's own when it is of the same
  # type, or a media slot's SVG template when the ref became an SVG.
  defp baseline(type, %{data: %{type: type, data: data}}), do: data
  defp baseline(type, %{type: type, data: data}), do: data
  defp baseline("svg", %{data: %{type: "media", data: data}}), do: data && data.template_svg
  defp baseline("svg", %{type: "media", data: data}), do: data && data.template_svg
  defp baseline(_type, _source), do: nil

  defp markup(_type, nil), do: %{}
  defp markup(type, data), do: Map.new(@markup[type], &{&1, Map.get(data, &1)})

  defp comparable("html", markup),
    do: {Map.get(markup, :text), Enum.map(Map.get(markup, :params) || [], &param/1)}

  defp comparable("svg", markup), do: {Map.get(markup, :code), Map.get(markup, :class)}

  defp comparable("media", markup) do
    case Map.get(markup, :template_svg) do
      nil -> {nil, nil}
      template -> comparable("svg", markup("svg", template))
    end
  end

  defp param(param), do: {field(param, :key), field(param, :label), to_string(field(param, :type))}

  defp field(param, key), do: Map.get(param, key, Map.get(param, Atom.to_string(key)))

  defp restore(ref, %{data: data} = new, allowed) do
    type = type(new)
    cleared = Map.new(@markup[type], &{&1, nil})
    data = struct(data, Map.merge(cleared, allowed))
    data = if type == "html", do: %{data | params: data.params || []}, else: data
    ref = put_data(ref, %{new | data: data})

    case type do
      "html" ->
        case HtmlBlock.invalid_keys(data) do
          [] ->
            ref

          keys ->
            Changeset.add_error(ref, :data, "has an invalid value for %{keys}",
              keys: Enum.join(keys, ", "),
              validation: :html_params
            )
        end

      _ ->
        ref
    end
  end

  defp put_data(ref, data) do
    errors = Keyword.delete(ref.errors, :data)
    ref = %{ref | errors: errors}
    ref = Changeset.force_change(ref, :data, data)
    %{ref | valid?: ref.errors == [] and nested_valid?(ref)}
  end

  defp nested_valid?(%Changeset{changes: changes}) do
    Enum.all?(changes, fn
      {_key, %Changeset{} = changeset} -> valid?(changeset)
      {_key, list} when is_list(list) -> Enum.all?(list, &valid?/1)
      _ -> true
    end)
  end

  defp valid?(%Changeset{action: :ignore}), do: true
  defp valid?(%Changeset{valid?: valid?}), do: valid?
  defp valid?(_), do: true

  # A ref in a saved block of the same module, with the same name and this
  # markup: a copy of a saved block brings its refs' markup along.
  defp stored?(state, ref, type, data) do
    module_id = Changeset.get_field(state.block, :module_id)
    name = Changeset.get_field(ref, :name)
    markup = comparable(type, markup(type, data))

    if module_id && name && type != "media" do
      {field, value} = if type == "html", do: {"text", data.text}, else: {"code", data.code}

      query =
        from r in Ref,
          join: b in Block,
          on: b.id == r.block_id,
          where:
            b.module_id == ^module_id and r.name == ^name and fragment("?->>'type'", r.data) == ^type and
              fragment("?->'data'->>?", r.data, ^field) == ^value,
          select: r.data,
          limit: 50

      not is_nil(value) and
        Enum.any?(Brando.Repo.all(query), &(comparable(type, markup(type, &1.data)) == markup))
    else
      false
    end
  end

  defp definition(%{module: :unloaded, block: block} = state, name) do
    module =
      case Changeset.get_field(block, :module_id) do
        nil -> nil
        id -> Brando.Content.fetch_module(id, Changeset.get_field(block, :module_origin) || :local)
      end

    definition(%{state | module: module}, name)
  end

  defp definition(%{module: %{refs: refs}} = state, name) when is_list(refs),
    do: {Enum.find(refs, &(&1.name == name)), state}

  defp definition(state, _name), do: {nil, state}

  defp superuser?(%{superuser: :unknown, user: user} = state) do
    superuser? = Boundary.superuser?(actor(user))
    {%{state | superuser: superuser?}, superuser?}
  end

  defp superuser?(%{superuser: superuser?} = state), do: {state, superuser?}

  defp actor(id) when is_integer(id), do: %{id: id}
  defp actor(user), do: user

  defp applied(%Changeset{} = changeset), do: Changeset.apply_changes(changeset)
  defp applied(data), do: data

  defp type(%{type: type}), do: to_string(type)
  defp type(_), do: nil
end
