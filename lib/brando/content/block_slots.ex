defmodule Brando.Content.BlockSlots do
  @moduledoc """
  Owned block collections shared by named refs and rich-text footnotes.

  Slots are internal nodes in the ordinary block tree. Ref rows address them;
  they do not own them, so replacing a ref cannot delete its content.
  """
  alias Brando.Content.Block
  alias Ecto.Changeset

  def children(%{children: children}) when is_list(children), do: children
  def children(%Changeset{} = changeset), do: Changeset.get_assoc(changeset, :children, :struct)
  def children(_), do: []

  def named(owner, name) do
    Enum.find(children(owner), &(&1.type == :slot && &1.slot_kind == :region && &1.slot_name == name))
  end

  def footnotes(owner), do: Enum.filter(children(owner), &(&1.type == :slot && &1.slot_kind == :footnote))

  def build(kind, name, module_set, source, user_id, uid \\ Brando.Utils.generate_uid()) do
    %Block{
      uid: uid,
      type: :slot,
      slot_kind: kind,
      slot_name: name,
      slot_module_set: module_set || "all",
      source: source,
      creator_id: user_id,
      children: [],
      refs: [],
      vars: [],
      table_rows: [],
      block_identifiers: []
    }
    |> Changeset.change()
    |> Map.put(:action, :insert)
  end

  @doc "Modules suitable for one level of a collection. Nested collections are intentionally excluded."
  def suitable_module?(%{multi: true}), do: false
  def suitable_module?(%{parent_id: id}) when not is_nil(id), do: false

  def suitable_module?(%{refs: refs}) when is_list(refs) do
    Enum.all?(refs, fn
      %{data: %{type: "blocks"}} -> false
      %{data: %{type: "text", data: %{footnotes: true}}} -> false
      _ -> true
    end)
  end

  def suitable_module?(_), do: false

  def modules(set) when set in [nil, "", "all"] do
    case Brando.Content.list_modules(%{preload: [:refs], order: "asc sequence"}) do
      {:ok, modules} -> prepare_modules(modules)
      _ -> []
    end
  end

  def modules(set) do
    case Brando.Content.get_module_set(%{matches: %{title: set}, preload: [module_set_modules: [module: :refs]]}) do
      {:ok, set} -> set.module_set_modules |> Enum.map(& &1.module) |> prepare_modules()
      _ -> []
    end
  end

  defp prepare_modules(modules) do
    modules |> Enum.filter(&suitable_module?/1) |> Enum.map(&Map.put(&1, :library_origin, :local))
  end

  def allowed_child?(child, allowed) do
    child.type == :module && children(child) == [] &&
      Enum.any?(allowed, &(&1.id == child.module_id && &1.library_origin == (child.module_origin || :local)))
  end

  def validate(%Changeset{} = changeset) do
    if changeset.data.type == :slot || Changeset.get_field(changeset, :type) == :slot do
      changeset =
        changeset
        |> keep_slot_identity()
        |> Changeset.validate_required([:slot_kind, :slot_name, :slot_module_set])

      allowed = modules(Changeset.get_field(changeset, :slot_module_set))
      retained = children(changeset.data)

      if Enum.all?(children(changeset), fn child ->
           allowed_child?(child, allowed) || Enum.any?(retained, &same_module?(&1, child))
         end) do
        changeset
      else
        Changeset.add_error(changeset, :children, "contains a module that is not allowed in this collection")
      end
    else
      validate_owned_slots(changeset)
    end
  end

  # Slot identity is server-owned. A ref being renamed or switched off does
  # not re-home its old notes, and posted hidden fields cannot change policy.
  defp keep_slot_identity(%{data: %{id: nil}} = changeset), do: changeset

  defp keep_slot_identity(changeset) do
    Enum.reduce([:type, :slot_kind, :slot_name, :slot_module_set], changeset, fn field, cs ->
      Changeset.put_change(cs, field, Map.get(cs.data, field))
    end)
  end

  defp same_module?(a, b),
    do:
      a.uid == b.uid && a.type == :module && b.type == :module &&
        a.module_id == b.module_id && a.module_origin == b.module_origin && children(b) == []

  @doc false
  def allowed_for_refs?(%{slot_kind: kind, slot_name: name, slot_module_set: set}, refs) do
    Enum.any?(refs, fn
      %{name: ^name, data: %{type: "text", data: %{footnotes: true, footnote_module_set: ^set}}} -> kind == :footnote
      %{name: ^name, data: %{type: "blocks", data: %{module_set: ^set}}} -> kind == :region
      _ -> false
    end)
  end

  defp validate_owned_slots(changeset) do
    retained = MapSet.new(children(changeset.data), & &1.uid)
    new_slots = Enum.filter(children(changeset), &(&1.type == :slot && !MapSet.member?(retained, &1.uid)))

    if new_slots == [] do
      changeset
    else
      module =
        Brando.Content.fetch_module(
          Changeset.get_field(changeset, :module_id),
          Changeset.get_field(changeset, :module_origin) || :local
        )

      refs =
        case module do
          %{refs: refs} when is_list(refs) -> refs
          _ -> []
        end

      if Enum.all?(new_slots, &allowed_for_refs?(&1, refs)) do
        changeset
      else
        Changeset.add_error(changeset, :children, "contains a collection that is not enabled by this module’s refs")
      end
    end
  end

  @doc false
  def validate_entry_slot(changeset, field, schema) do
    block = Changeset.get_assoc(changeset, :block, :struct)

    configured =
      if function_exported?(schema, :__form__, 0),
        do: schema.__form__() |> Brando.Blueprint.Forms.Footnotes.fields(),
        else: %{}

    note_owner? = Enum.any?(configured, fn {_name, config} -> config.blocks == field end)

    cond do
      block && note_owner? && block.type != :slot ->
        Changeset.add_error(changeset, :block, "this field only stores its configured footnotes")

      block && block.type == :slot && is_nil(block.id) ->
        allowed =
          Enum.any?(configured, fn {name, config} ->
            config.enabled && config.blocks == field && to_string(name) == block.slot_name &&
              config.module_set == block.slot_module_set && block.slot_kind == :footnote
          end)

        if allowed,
          do: changeset,
          else: Changeset.add_error(changeset, :block, "footnotes are not enabled for this field")

      true ->
        changeset
    end
  end

  def uid_mapping(block) do
    Map.new([block | descendants(block)], &{&1.uid, Brando.Utils.generate_uid()})
  end

  defp descendants(block), do: Enum.flat_map(children(block), &[&1 | descendants(&1)])

  def remap_markers(html, mapping) when is_binary(html) do
    if String.contains?(html, "data-footnote-uid") do
      html
      |> Floki.parse_fragment!()
      |> Floki.traverse_and_update(fn
        {tag, attrs, children} ->
          attrs =
            Enum.map(attrs, fn
              {"data-footnote-uid", uid} -> {"data-footnote-uid", Map.get(mapping, uid, uid)}
              other -> other
            end)

          {tag, attrs, children}

        node ->
          node
      end)
      |> Floki.raw_html()
    else
      html
    end
  end

  def remap_markers(value, _mapping), do: value
end
