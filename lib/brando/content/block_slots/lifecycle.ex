defmodule Brando.Content.BlockSlots.Lifecycle do
  @moduledoc "Inspection and explicit recovery of collections whose insertion point is gone."
  alias Brando.Content.BlockSlots
  alias Ecto.Changeset

  @salt "brando-region-remap"

  def marker_uids(html) when is_binary(html) do
    html
    |> Floki.parse_fragment!()
    |> Floki.find("sup[data-footnote-uid], span[data-footnote-uid]")
    |> Floki.attribute("data-footnote-uid")
    |> MapSet.new()
  end

  def marker_uids(_), do: MapSet.new()

  def definitions(%{module_id: nil}), do: []

  def definitions(owner) do
    case Brando.Content.fetch_module(owner.module_id, owner.module_origin || :local) do
      %{refs: refs} when is_list(refs) -> refs
      _ -> []
    end
  end

  def unused(owner, definitions) do
    Enum.filter(BlockSlots.children(owner), &unused?(&1, owner, definitions))
  end

  def unused?(%{type: :slot, slot_kind: :region, slot_name: name}, _owner, definitions),
    do: !Enum.any?(definitions, &match?(%{name: ^name, data: %{type: "blocks"}}, &1))

  def unused?(%{type: :slot, slot_kind: :footnote, slot_name: name, uid: uid}, owner, definitions) do
    !text_ref?(definitions, name) || !MapSet.member?(marker_uids(text(owner, name)), uid)
  end

  def unused?(_, _, _), do: false

  def text_ref?(refs, name), do: Enum.any?(refs, &match?(%{name: ^name, data: %{type: "text"}}, &1))

  def text(owner, name) do
    Enum.find_value(owner.refs, fn
      %{name: ^name, data: %{type: "text", data: %{text: text}}} -> text
      _ -> nil
    end)
  end

  def unused_notes(slots, field, html) do
    referenced = marker_uids(html)
    name = to_string(field)

    Enum.filter(slots, fn slot ->
      slot.type == :slot && slot.slot_kind == :footnote && slot.slot_name == name &&
        !MapSet.member?(referenced, slot.uid)
    end)
  end

  def label(%{slot_kind: :region, slot_name: name}), do: name

  def label(slot) do
    text =
      slot
      |> BlockSlots.children()
      |> Enum.flat_map(fn child -> List.wrap(child.refs) end)
      |> Enum.find_value(fn
        %{data: %{type: "text", data: %{text: html}}} when is_binary(html) ->
          text = html |> Floki.parse_fragment!() |> Floki.text() |> String.trim()
          if text != "", do: text

        _ ->
          nil
      end)

    case text do
      nil -> slot.slot_name
      text -> if String.length(text) > 80, do: String.slice(text, 0, 80) <> "…", else: text
    end
  end

  def remap_targets(owner, definitions, uid) do
    case Enum.find(unused(owner, definitions), &(&1.uid == uid && &1.slot_kind == :region)) do
      nil -> []
      slot -> Enum.filter(definitions, &remap_target?(&1, owner, slot))
    end
  end

  defp remap_target?(%{name: name, data: %{type: "blocks", data: %{module_set: set}}}, owner, slot) do
    destination = BlockSlots.named(owner, name)
    allowed = BlockSlots.modules(set)

    name != slot.slot_name && (is_nil(destination) || BlockSlots.children(destination) == []) &&
      Enum.all?(BlockSlots.children(slot), &BlockSlots.allowed_child?(&1, allowed))
  end

  defp remap_target?(_, _, _), do: false

  @doc "Authorize a specific remap after checking the current owner tree and module definition."
  def remap(owner, definitions, uid, name) do
    with %{data: %{data: %{module_set: set}}} <- Enum.find(remap_targets(owner, definitions, uid), &(&1.name == name)),
         slot when not is_nil(slot) <- Enum.find(BlockSlots.children(owner), &(&1.uid == uid)) do
      claim = %{
        uid: uid,
        id: slot.id,
        owner_uid: owner.uid,
        from: slot.slot_name,
        name: name,
        set: set,
        prefix: Brando.Tenant.current_prefix()
      }

      token = Phoenix.Token.sign(Brando.endpoint(), @salt, claim)
      destination = BlockSlots.named(owner, name)

      {:ok, destination && destination.uid, %{"slot_name" => name, "slot_module_set" => set, "slot_remap" => token}}
    else
      _ -> {:error, :invalid_destination}
    end
  end

  # The signed operation travels with DOM recovery, drafts and op snapshots.
  # Ordinary posted metadata still cannot change a persisted slot's identity.
  # Current definitions and the actual parent are checked again on every save.
  def remap_claim(%Changeset{} = cs) do
    token = Changeset.get_field(cs, :slot_remap)

    with true <- is_binary(token),
         {:ok, claim} <- Phoenix.Token.verify(Brando.endpoint(), @salt, token, max_age: :infinity),
         true <- claim.uid == Changeset.get_field(cs, :uid),
         true <- claim.id == cs.data.id,
         true <- claim.prefix == Brando.Tenant.current_prefix(),
         true <- Changeset.get_field(cs, :slot_kind) == :region,
         true <- is_nil(cs.data.id) || cs.data.slot_name in [claim.from, claim.name] do
      {:ok, claim}
    else
      _ -> :error
    end
  end

  def validate_remaps(owner_cs) do
    remapped = Enum.filter(Changeset.get_assoc(owner_cs, :children), &Changeset.get_field(&1, :slot_remap))

    if remapped == [] do
      owner_cs
    else
      owner = Changeset.apply_changes(owner_cs)
      definitions = definitions(owner)

      valid? =
        Enum.all?(remapped, fn cs ->
          with {:ok, claim} <- remap_claim(cs),
               true <- claim.owner_uid == owner.uid,
               true <-
                 !Enum.any?(definitions, &match?(%{name: name, data: %{type: "blocks"}} when name == claim.from, &1)),
               true <-
                 Enum.count(BlockSlots.children(owner), &(&1.slot_kind == :region && &1.slot_name == claim.name)) == 1,
               true <- BlockSlots.allowed_for_refs?(Changeset.apply_changes(cs), definitions) do
            allowed = BlockSlots.modules(claim.set)
            Enum.all?(BlockSlots.children(cs), &BlockSlots.allowed_child?(&1, allowed))
          else
            _ -> false
          end
        end)

      if valid?, do: owner_cs, else: Changeset.add_error(owner_cs, :children, "the region remap is no longer available")
    end
  end
end
