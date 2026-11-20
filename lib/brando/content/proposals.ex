defmodule Brando.Content.Proposals do
  use Gettext, backend: Brando.Gettext

  @moduledoc """
  Reviewed content changes across several saved entries.

  A proposal is a list of semantic operations — `CreateEntry`, `CreateTranslation`,
  `SetFields`, `InsertBlock`, `SetBlockMedia`, `SetBlockValues`, `SetBlockText`, `MoveBlock`,
  `DeleteBlock` and the others in `Brando.Content.Proposals.Codec` — that
  `prepare/2` resolves against the actor's content,
  validates and freezes. Block operations address any block of a field by its
  uid, including the children of multi modules, containers and slots, and
  are checked in order against the field as the earlier operations leave it
  (`Brando.Content.Proposals.BlockTree`). Nothing is written until `apply/2`:

      {:ok, proposal} = Proposals.prepare(operations, user)
      [] = proposal.problems
      {:ok, changesets} = Proposals.materialize(proposal, user)
      {:ok, receipt} = Proposals.apply(proposal, user)

  `materialize/2` builds each entry's changeset in memory from the frozen
  operations, which is what review and page previews render. `apply/2` builds
  the same changesets again under row locks, refuses if any entry or module
  changed since `prepare/2`, and saves through the generated context
  mutations, so identifiers, publishing jobs, cascades and revisions run as
  they do for an editor's save. New entries are always drafts; existing
  entries keep their status, and `effects.live` lists the published ones the
  proposal changes. Applying a proposal twice returns the first receipt.

  Block values cannot yet reference an entry the proposal creates — the entry
  would be a draft — so such a value is a blocking `:draft_dependency`.

  A `CreateTranslation` makes the source's copy in its synchronized group
  when the proposal is applied (`Brando.Translations.create_target/5`), so
  the copy has no blocks before then: other operations may not name it as
  `{:new, ref}` (`:use_translate`). `translation/2` gives the operation that
  creates a `{:new, ref}` translation, its source and language.

  A `Translate` answers a batch of a synchronized translation's work
  (`Brando.Translations.Work`): checked against the units as they are now,
  and saved as the translation's form saves it
  (`Brando.Translations.save_work/5`), not through the plain update the other
  operations use. It is the only operation a proposal may have on the
  translation it translates (`:translate_only`); on `{:new, ref}` it fills
  in the translation a `CreateTranslation` creates, once it is created.

  `ReplaceImageFile` changes no entry: a library image takes another's file
  (`Brando.Content.Proposals.ImageReplacement`), in the same transaction as
  the entries. A proposal that replaced a file cannot be undone.
  """
  import Ecto.Query, only: [from: 2]
  import Kernel, except: [apply: 3]

  alias Brando.Authorization.Boundary
  alias Brando.Content
  alias Brando.Content.Blocks
  alias Brando.Content.BlockSlots
  alias Brando.Content.Proposals.Baseline
  alias Brando.Content.Proposals.BlockTree
  alias Brando.Content.Proposals.Codec
  alias Brando.Content.Proposals.CopyBlock
  alias Brando.Content.Proposals.CreateEntry
  alias Brando.Content.Proposals.CreateTranslation
  alias Brando.Content.Proposals.DeleteBlock
  alias Brando.Content.Proposals.EntryFields
  alias Brando.Content.Proposals.EntryLinks
  alias Brando.Content.Proposals.ImageReplacement
  alias Brando.Content.Proposals.InsertBlock
  alias Brando.Content.Proposals.MoveBlock
  alias Brando.Content.Proposals.Proposal
  alias Brando.Content.Proposals.Receipt
  alias Brando.Content.Proposals.Record
  alias Brando.Content.Proposals.RefConfig
  alias Brando.Content.Proposals.ReplaceImageFile
  alias Brando.Content.Proposals.SetBlockActive
  alias Brando.Content.Proposals.SetBlockDetails
  alias Brando.Content.Proposals.SetBlockMedia
  alias Brando.Content.Proposals.SetBlockSelection
  alias Brando.Content.Proposals.SetBlockTable
  alias Brando.Content.Proposals.SetBlockText
  alias Brando.Content.Proposals.SetBlockValues
  alias Brando.Content.Proposals.SetFields
  alias Brando.Content.Proposals.SetRefConfig
  alias Brando.Content.Proposals.Translate
  alias Brando.Content.Transfer
  alias Brando.Content.Transfer.Catalog
  alias Brando.Content.Transfer.Dependencies
  alias Brando.Content.Transfer.Error
  alias Brando.Drafts.Params
  alias Brando.Repo
  alias Brando.Translations
  alias Brando.Translations.Work
  alias Brando.Utils
  alias BrandoAdmin.Components.Form.LockedFields
  alias Ecto.Changeset

  @protected_fields ~w(id status publish_at unpublish_at deleted_at marked_as_deleted creator_id inserted_at updated_at)
  @text_vars [:string, :text, :rich_text]
  @media_kinds %{image: "picture", video: "video", gallery: "gallery", file: "file"}
  # A uid chosen for a new block leaves room within what `Content.Block.valid_uid?/1`
  # admits for the suffix of a copy made of it: the edit session rescues a block
  # removed under an editor as `<uid>-kept`.
  @new_uid_bytes 128

  ## Prepare

  @doc """
  Resolve, validate and freeze `operations` for `actor`.

  Returns `{:error, message}` when a target cannot be loaded or the actor is
  outside the current site/environment. Validation problems do not fail; they
  are listed in `proposal.problems` and block `apply/2`.
  """
  @spec prepare([struct()], term()) :: {:ok, Proposal.t()} | {:error, String.t()}
  def prepare(operations, actor), do: Error.protect(fn -> prepare!(operations, actor) end)

  defp prepare!(operations, actor) do
    Transfer.ensure_scope!(actor)
    user = user!(actor)
    operations = Enum.map(operations, &(&1 |> freeze() |> EntryLinks.resolve(actor) |> snapshot(actor)))
    catalogued!(operations)
    creates = creates(operations)

    entries =
      operations
      |> Enum.flat_map(&op_targets/1)
      |> Enum.filter(&match?({schema, id} when is_atom(schema) and schema != :new and not is_nil(id), &1))
      |> Enum.uniq()
      |> Map.new(fn target -> {target, load!(target, actor)} end)

    operations = Enum.map(operations, &copy_texts(&1, operations, entries))

    proposal = %Proposal{
      id: Ecto.UUID.generate(),
      scope: Transfer.scope(),
      actor_id: user.id,
      operations: operations,
      targets: Map.merge(entries, creates),
      fingerprints: Map.new(entries, fn {target, entry} -> {target, Transfer.entry_fingerprint(entry)} end),
      module_versions: module_versions(operations)
    }

    problems = operation_problems(proposal, actor)
    problems = if problems == [], do: check_changesets(proposal, entries, user), else: problems
    %{proposal | problems: problems, effects: effects(proposal)}
  end

  # A text given as `{:from, uid, ref}` (`Codec`) is that saved block's text,
  # copied as it is stored, so an agent can move a long text to a block of
  # another module without writing it out again. The copy is checked and
  # reviewed as any other text.
  defp copy_texts(%InsertBlock{} = op, _operations, entries) do
    texts =
      Map.new(op.texts, fn {name, text} -> {name, copied_text(text, slot_type(op.module, name), op, entries)} end)

    %{op | texts: texts}
  end

  defp copy_texts(%SetBlockText{} = op, operations, entries),
    do: %{op | text: copied_text(op.text, block_slot_type(op, operations, entries), op, entries)}

  defp copy_texts(op, _operations, _entries), do: op

  defp copied_text({:from, uid, name}, slot_type, op, entries) do
    case saved_text(entries, op.target, op.field, uid, name) do
      nil ->
        Error.fail!(
          dgettext(
            "content_proposals",
            "There is no saved text %{ref} in block %{uid} of this entry and field to copy.",
            ref: name,
            uid: uid
          )
        )

      {_type, ""} ->
        Error.fail!(dgettext("content_proposals", "Text %{ref} in block %{uid} is empty.", ref: name, uid: uid))

      {type, text} ->
        cond do
          # Its notes are slots of the block it is in; a copy would point at none.
          String.contains?(text, "data-footnote-uid") ->
            Error.fail!(
              dgettext(
                "content_proposals",
                "Text %{ref} in block %{uid} has footnotes, which stay with their block, so it cannot be copied.",
                ref: name,
                uid: uid
              )
            )

          # Markdown leaves rich text's markup out, rich text and headings
          # would show Markdown's as it is, and Markdown would read a
          # heading's * and _ as markup.
          type != slot_type and "markdown" in [type, slot_type] and slot_type != nil ->
            Error.fail!(
              dgettext(
                "content_proposals",
                "Text %{ref} in block %{uid} is %{from}, and the slot takes %{to}: write it out in that form instead.",
                ref: name,
                uid: uid,
                from: text_kind(type),
                to: text_kind(slot_type)
              )
            )

          true ->
            text
        end
    end
  end

  defp copied_text(text, _slot_type, _op, _entries), do: text

  defp text_kind("markdown"), do: dgettext("content_proposals", "Markdown")
  defp text_kind("header"), do: dgettext("content_proposals", "plain text")
  defp text_kind(_text), do: dgettext("content_proposals", "rich text")

  defp saved_text(entries, target, field, uid, name) do
    with %{} = block <- saved_entry_block(entries, target, field, uid),
         %{data: %{type: type, data: %{text: text}}} when type in ~w(text header markdown) <-
           Enum.find(block.refs || [], &(&1.name == name)) do
      {type, text || ""}
    else
      _ -> nil
    end
  end

  defp saved_entry_block(entries, target, field, uid) do
    with %{} = entry <- Map.get(entries, target),
         {block, _parent, _index} <- BlockTree.find_saved(entry_blocks(entry, field), uid) do
      block
    else
      _ -> nil
    end
  end

  # The type of the slot a copied text goes into, when it is known before
  # validation: a saved block's, or that of a block an operation inserts.
  defp block_slot_type(op, operations, entries) do
    name = to_string(op.ref)

    case saved_entry_block(entries, op.target, op.field, op.block_uid) do
      %{refs: refs} ->
        ref_type(refs, name)

      nil ->
        Enum.find_value(operations, fn
          %InsertBlock{uid: uid, module: module} when uid == op.block_uid ->
            slot_type(module, name)

          # A copy has the refs of the saved block it copies.
          %CopyBlock{uid: uid} = copy when uid == op.block_uid ->
            case saved_entry_block(entries, copy.target, copy.field, copy.block_uid) do
              %{refs: refs} -> ref_type(refs, name)
              nil -> nil
            end

          _ ->
            nil
        end)
    end
  end

  defp slot_type(module, name) do
    case fetch_module(module) do
      %{refs: refs} -> ref_type(refs, to_string(name))
      _ -> nil
    end
  end

  defp ref_type(refs, name) when is_list(refs) do
    Enum.find_value(refs, fn
      %{name: ^name, data: %{type: type}} -> type
      _ -> nil
    end)
  end

  defp ref_type(_refs, _name), do: nil

  # A proposal creates and changes entries only of the content types
  # `list_content_types` lists (`Codec.writable_schema/1`): Brando's internal
  # schemas, such as users, global sets, menus or vars, and palettes, which
  # a proposal may only pick, are refused before anything is stored.
  defp catalogued!(operations) do
    for op <- operations, schema <- written_schemas(op), Codec.writable_schema(schema) != {:ok, schema} do
      Error.fail!(Codec.unwritable_message(schema))
    end

    :ok
  end

  defp written_schemas(%CreateEntry{schema: schema}), do: [schema]
  defp written_schemas(%CreateTranslation{source: {schema, _id}}), do: [schema]
  defp written_schemas(op), do: for({schema, _id} <- op_targets(op), schema != :new, do: schema)

  @doc """
  Whether the proposed version of `proposal` may be rendered for review:
  only when it has no problems. With a problem, an operation's text may not
  have been checked (a block that is not where it should be, a ref its
  module no longer has), while the page would still be built from it. The
  operations are checked again, as the user who prepared the proposal: one
  stored before a check was added or tightened keeps its old problem list.
  """
  @spec previewable?(Proposal.t()) :: boolean()
  def previewable?(%Proposal{problems: problems} = proposal) when problems in [nil, []] do
    with %Brando.Users.User{} = owner <- Repo.get(Brando.Users.User, proposal.actor_id),
         # In the owner's scope too: queries read the process scope, and a
         # colleague's could hide what the owner may use.
         scope = Boundary.actor_scope(owner),
         {:ok, []} <- Boundary.with_scope(scope, fn -> recheck(proposal, scope) end) do
      true
    else
      _ -> false
    end
  end

  def previewable?(%Proposal{}), do: false

  defp recheck(proposal, actor), do: Error.protect(fn -> operation_problems(proposal, actor) end)

  # `failed` holds the uids of blocks an earlier insert or copy could not
  # add, with that operation's index: an operation on one of them is told
  # so, not that the block is unknown.
  defp operation_problems(proposal, actor) do
    {problems, _acc} =
      proposal.operations
      |> Enum.with_index()
      |> Enum.flat_map_reduce({%{}, %{}}, fn {op, index}, {trees, failed} ->
        {problems, trees} =
          case failed_reference(op, proposal, trees, failed) do
            nil -> check_operation(op, proposal, actor, trees)
            problem -> {[problem], trees}
          end

        failed = record_failure(op, index, problems, trees, failed)
        {Enum.map(problems, &Map.put(&1, :operation, index)), {trees, failed}}
      end)

    problems
  end

  defp check_operation(%Translate{} = op, proposal, actor, trees),
    do: {translate_problems(op, proposal, actor), trees}

  defp check_operation(op, proposal, actor, trees) do
    cond do
      Enum.any?(op_targets(op), &translation(proposal.operations, &1)) ->
        {[use_translate()], trees}

      Enum.any?(op_targets(op), &translated?(proposal.operations, &1)) ->
        {[translate_only()], trees}

      true ->
        {problems, trees} = check(op, proposal, actor, trees)
        {copy_problems, trees} = check_copy_destination(op, proposal, actor, trees)
        {problems ++ copy_problems ++ link_problems(op), trees}
    end
  end

  # The translate operation saves through the translation's own save, which
  # no other operation's change would go through.
  defp translate_only,
    do:
      problem(
        :translate_only,
        dgettext(
          "content_proposals",
          "A translate operation in this proposal fills in this translation, and it can be the only kind of operation on it: its structure follows its source, and its text is saved as its translation form saves it. Put this change in another proposal, or the text in the translate operation."
        )
      )

  # A translation the proposal creates has no blocks until it is applied, and
  # its structure follows its source: only its text is its own.
  defp use_translate,
    do:
      problem(
        :use_translate,
        dgettext(
          "content_proposals",
          "This entry is the translation an earlier operation creates. Its blocks and fields are copied from its source when the proposal is applied, and its structure follows the source: write its text with a translate operation instead."
        )
      )

  # An insert or copy that adds its uid clears an earlier failure of it.
  defp record_failure(%op_type{uid: uid} = op, index, problems, trees, failed) when op_type in [InsertBlock, CopyBlock] do
    key = new_block_key(op)
    tree = Map.get(trees, key, %BlockTree{})

    cond do
      BlockTree.fetch(tree, uid) != nil -> Map.delete(failed, {key, uid})
      problems != [] -> Map.put(failed, {key, uid}, index)
      true -> failed
    end
  end

  defp record_failure(_op, _index, _problems, _trees, failed), do: failed

  defp new_block_key(%CopyBlock{to_target: to} = op) when not is_nil(to), do: {to, op.to_field}
  defp new_block_key(op), do: {op.target, op.field}

  defp failed_reference(_op, _proposal, _trees, failed) when map_size(failed) == 0, do: nil

  defp failed_reference(op, proposal, trees, failed) do
    Enum.find_value(block_references(op), &failed_block(&1, proposal, trees, failed))
  end

  # A block an earlier operation failed to add, unless the field has a
  # block with that uid after all. A missing target or field is left to
  # the operation's own check.
  defp failed_block({role, uid, {target, field} = key}, proposal, trees, failed) do
    with index when is_integer(index) <- Map.get(failed, {key, uid}),
         {:ok, schema} <- target_schema(target, proposal),
         :ok <- block_field(schema, field),
         tree = Map.get_lazy(trees, key, fn -> saved_tree(target, field, proposal) end),
         nil <- BlockTree.fetch(tree, uid) do
      failed_problem(role, uid, index)
    else
      _ -> nil
    end
  end

  # The blocks an operation names, with the field each is looked up in.
  defp block_references(%InsertBlock{field: field} = op) when is_binary(field) do
    key = {op.target, field}
    if(op.parent, do: [{:parent, op.parent, key}], else: []) ++ anchor_reference(op.placement, key)
  end

  defp block_references(%{block_uid: uid, field: field} = op) when is_binary(uid) and is_binary(field) do
    [{:block, uid, {op.target, field}} | anchor_reference(Map.get(op, :placement), new_block_key(op))]
  end

  defp block_references(_op), do: []

  defp anchor_reference({side, anchor}, key) when side in [:before, :after, :into] and is_binary(anchor),
    do: [{:anchor, anchor, key}]

  defp anchor_reference(_placement, _key), do: []

  defp failed_problem(:parent, uid, index),
    do:
      problem(
        :parent_failed,
        dgettext("content_proposals", "Not inserted: its parent `%{uid}` failed (operation %{operation}).",
          uid: uid,
          operation: index
        )
      )

  defp failed_problem(:anchor, uid, index),
    do:
      problem(
        :parent_failed,
        dgettext(
          "content_proposals",
          "Not applied: the block to place it next to, `%{uid}`, failed (operation %{operation}).",
          uid: uid,
          operation: index
        )
      )

  defp failed_problem(:block, uid, index),
    do:
      problem(
        :parent_failed,
        dgettext("content_proposals", "Not applied: the block `%{uid}` failed (operation %{operation}).",
          uid: uid,
          operation: index
        )
      )

  # The entries an operation touches: its target, and a copy's destination.
  defp op_targets(%CopyBlock{target: target, to_target: to}) when not is_nil(to), do: [target, to]
  # A translation's source is read when the operation is checked and copied
  # as it is when the proposal is applied: it is not one of the entries the
  # proposal changes or holds a baseline of.
  defp op_targets(%CreateTranslation{}), do: []
  defp op_targets(op), do: [Map.get(op, :target)]

  # The new entries, `{:new, ref} => schema`: created entries and translations.
  defp creates(operations) do
    Map.new(
      for %type{ref: ref} = op <- operations, type in [CreateEntry, CreateTranslation], do: {{:new, ref}, new_schema(op)}
    )
  end

  defp new_schema(%CreateEntry{schema: schema}), do: schema
  defp new_schema(%CreateTranslation{source: {schema, _id}}), do: schema

  @doc """
  The `CreateTranslation` among `operations` that creates `target`, or `nil`:
  `{:new, ref}` resolves to the translation of its `source` in its `language`.
  """
  @spec translation([struct()], Proposal.target()) :: CreateTranslation.t() | nil
  def translation(operations, {:new, ref}),
    do: Enum.find(operations, &match?(%CreateTranslation{ref: ^ref}, &1))

  def translation(_operations, _target), do: nil

  @doc "Whether a `Translate` among `operations` translates `target`."
  @spec translated?([struct()], Proposal.target()) :: boolean()
  def translated?(operations, target), do: Enum.any?(operations, &match?(%Translate{target: ^target}, &1))

  @doc """
  The entries `operations` only copy blocks from. They are read, to copy
  from, and locked while the proposal is applied, but not changed or saved.
  """
  @spec sources([struct()]) :: [Proposal.target()]
  def sources(operations) do
    changed = operations |> Enum.flat_map(&changed_targets/1) |> MapSet.new()

    for %CopyBlock{target: target, to_target: to} <- operations,
        not is_nil(to),
        not MapSet.member?(changed, target),
        uniq: true,
        do: target
  end

  defp changed_targets(%CopyBlock{to_target: to}) when not is_nil(to), do: [to]
  defp changed_targets(%CreateEntry{ref: ref}), do: [{:new, ref}]
  defp changed_targets(%CreateTranslation{ref: ref}), do: [{:new, ref}]
  defp changed_targets(op), do: [Map.get(op, :target)]

  defp freeze(%CreateEntry{} = op), do: %{op | ref: to_string(op.ref), fields: stringify(op.fields)}
  defp freeze(%CreateTranslation{} = op), do: %{op | ref: to_string(op.ref), language: to_string(op.language)}
  defp freeze(%SetFields{} = op), do: %{op | target: target(op.target), fields: stringify(op.fields)}

  defp freeze(%SetRefConfig{} = op),
    do: %{
      op
      | target: target(op.target),
        field: to_string(op.field),
        ref: to_string(op.ref),
        config: stringify(op.config)
    }

  defp freeze(%InsertBlock{} = op) do
    refs =
      case fetch_module(op.module) do
        %{refs: refs} when is_list(refs) -> refs
        _ -> []
      end

    %{
      op
      | target: target(op.target),
        field: to_string(op.field),
        parent: op.parent && to_string(op.parent),
        module: module_reference(op.module),
        uid: op.uid || Utils.generate_uid(),
        values: stringify(op.values),
        texts: stringify(op.texts),
        media: stringify(op.media),
        configs: Map.new(op.configs || %{}, fn {name, config} -> {to_string(name), stringify(config)} end),
        ref_uids: Map.new(refs, &{&1.name, op.ref_uids[&1.name] || Utils.generate_uid()})
    }
  end

  defp freeze(%SetBlockMedia{} = op), do: %{op | target: target(op.target), field: to_string(op.field)}

  defp freeze(%SetBlockText{} = op), do: %{op | target: target(op.target), field: to_string(op.field)}

  defp freeze(%SetBlockValues{} = op),
    do: %{op | target: target(op.target), field: to_string(op.field), values: stringify(op.values)}

  defp freeze(%MoveBlock{} = op), do: %{op | target: target(op.target), field: to_string(op.field)}

  defp freeze(%CopyBlock{} = op) do
    to_target = op.to_target && target(op.to_target)

    %{
      op
      | target: target(op.target),
        field: to_string(op.field),
        uid: op.uid || Utils.generate_uid(),
        to_target: to_target,
        to_field: to_target && to_string(op.to_field || op.field)
    }
  end

  defp freeze(%SetBlockDetails{} = op), do: %{op | target: target(op.target), field: to_string(op.field)}

  defp freeze(%SetBlockTable{} = op),
    do: %{op | target: target(op.target), field: to_string(op.field), rows: Enum.map(op.rows, &stringify/1)}

  defp freeze(%SetBlockSelection{} = op), do: %{op | target: target(op.target), field: to_string(op.field)}

  defp freeze(%SetBlockActive{} = op),
    do: %{op | target: target(op.target), field: to_string(op.field), ref: op.ref && to_string(op.ref)}

  defp freeze(%DeleteBlock{} = op), do: %{op | target: target(op.target), field: to_string(op.field)}
  defp freeze(%ReplaceImageFile{} = op), do: op
  defp freeze(%Translate{} = op), do: %{op | target: target(op.target)}

  # The files a replacement swaps, as they are now: never as the operation
  # given says.
  defp snapshot(%ReplaceImageFile{} = op, actor), do: ImageReplacement.snapshot(op, actor)
  defp snapshot(op, _actor), do: op

  defp module_reference(reference) do
    Content.SharedLibrary.reference(reference)
  rescue
    _ -> reference
  end

  defp target({:new, ref}), do: {:new, to_string(ref)}
  defp target(target), do: target

  defp stringify(map), do: Map.new(map || %{}, fn {key, value} -> {to_string(key), value} end)

  defp module_versions(operations) do
    for %InsertBlock{module: reference} <- operations,
        module = fetch_module(reference),
        into: %{},
        do: {Content.SharedLibrary.reference(reference), module.version || 1}
  end

  ## Validation

  # Block operations are checked against the field as the operations before
  # them leave it; `trees` holds that shape per `{target, field}`.
  defp check(%{field: field} = op, proposal, actor, trees) when is_binary(field) do
    with {:ok, schema} <- target_schema(op.target, proposal),
         :ok <- block_field(schema, field) do
      key = {op.target, field}
      tree = Map.get_lazy(trees, key, fn -> saved_tree(op.target, field, proposal) end)
      {problems, tree} = check_block(op, schema, tree, actor, proposal)
      {problems, Map.put(trees, key, tree)}
    else
      {:error, problem} -> {[problem], trees}
    end
  end

  defp check(op, proposal, actor, trees), do: {check(op, proposal, actor), trees}

  # The destination half of a copy to another entry or field.
  defp check_copy_destination(%CopyBlock{to_target: to} = op, proposal, actor, trees) when not is_nil(to) do
    source = {op.target, op.field}
    source_tree = Map.get_lazy(trees, source, fn -> saved_tree(op.target, op.field, proposal) end)
    saved? = saved_block_of(proposal, op.target, op.field, op.block_uid) != nil

    with {:ok, schema} <- target_schema(to, proposal),
         :ok <- block_field(schema, op.to_field),
         %{} = node <- BlockTree.fetch(source_tree, op.block_uid) || {:error, unknown_block()},
         true <- saved? || {:error, copy_unsaved()},
         key = {to, op.to_field},
         tree = Map.get_lazy(trees, key, fn -> saved_tree(to, op.to_field, proposal) end),
         :ok <- new_uid(op.uid, tree, actor),
         {:ok, parent} <- destination(op.placement, %{node | uid: op.uid, parent: nil}, tree, :copy),
         :ok <- movable(%{node | parent: :elsewhere}, parent, schema, op.to_field, tree) do
      {[], Map.put(trees, key, BlockTree.copy_from(source_tree, tree, node.uid, op.uid, parent, op.placement))}
    else
      {:error, problem} -> {[problem], trees}
    end
  end

  defp check_copy_destination(_op, _proposal, _actor, trees), do: {[], trees}

  defp copy_unsaved,
    do:
      problem(
        :unknown_block,
        dgettext("content_proposals", "Only a saved block can be copied to another entry or field.")
      )

  defp saved_block_of(proposal, target, field, uid) do
    with %{} = entry <- Map.get(proposal.targets, target),
         {block, _, _} <- BlockTree.find_saved(entry_blocks(entry, field), uid) do
      block
    else
      _ -> nil
    end
  end

  defp check(%CreateEntry{} = op, proposal, actor) do
    duplicate? = duplicate_ref?(op, proposal)

    problems =
      cond do
        duplicate? ->
          [problem(:duplicate_ref, dgettext("content_proposals", "Two new entries use the same reference."))]

        Codec.writable_schema(op.schema) != {:ok, op.schema} ->
          [problem(:unknown_schema, dgettext("content_proposals", "This content type is not registered on this site."))]

        Boundary.authorize(actor, :create, op.schema) != :ok ->
          [problem(:forbidden, dgettext("content_proposals", "You do not have permission to create this entry."))]

        true ->
          Enum.uniq(protected_fields(op.fields, op.schema) ++ locked_fields(op.fields, op.schema, actor)) ++
            asset_fields(op.fields, op.schema, actor) ++
            list_fields(op.fields, op.schema, actor) ++ draft_dependencies(op.fields, proposal)
      end

    # Text is checked whatever else is wrong: a preview renders it anyway.
    problems ++ text_fields(op.fields)
  end

  defp check(%CreateTranslation{source: {schema, id}} = op, proposal, actor) do
    cond do
      duplicate_ref?(op, proposal) ->
        [problem(:duplicate_ref, dgettext("content_proposals", "Two new entries use the same reference."))]

      not Translations.synchronized?(schema) ->
        [
          problem(
            :not_synchronized,
            dgettext(
              "content_proposals",
              "%{name} entries are not synchronized translations. Create the version in another language with create_entry instead.",
              name: Codec.content_type(schema)
            )
          )
        ]

      not Translations.duplicable?(schema) ->
        [
          problem(
            :not_duplicable,
            dgettext("content_proposals", "%{name} entries cannot be copied, so they cannot be translated.",
              name: Codec.content_type(schema)
            )
          )
        ]

      true ->
        source_problems(op, {schema, id}, proposal, actor)
    end
  end

  defp check(%ReplaceImageFile{} = op, proposal, actor),
    do: ImageReplacement.problems(op, proposal.operations, actor)

  defp check(%SetFields{target: {:new, _}}, _, _),
    do: [problem(:unknown_target, dgettext("content_proposals", "Set the fields of a new entry when creating it."))]

  defp check(%SetFields{} = op, proposal, actor) do
    {schema, _} = op.target
    {status, fields} = Map.split(op.fields, ["status"])

    Enum.uniq(protected_fields(fields, schema) ++ locked_fields(op.fields, schema, actor)) ++
      text_fields(fields) ++
      status_problems(status, schema, proposal.targets[op.target], actor) ++
      asset_fields(op.fields, schema, actor) ++
      list_fields(op.fields, schema, actor) ++ draft_dependencies(op.fields, proposal)
  end

  ## Translate

  # Checked against the translation's units as they are now: those of its
  # pending version, or, for `{:new, ref}`, those the translation the proposal
  # creates will have. Every problem names its unit.
  defp translate_problems(%Translate{} = op, proposal, actor) do
    case translate_work(op, proposal, actor) do
      {:ok, schema, scope, units} ->
        answer = %{texts: op.texts, reviewed: op.reviewed}
        # Only a unit answered with text has a source and a format
        by_key = for %{answerable: true} = unit <- units, into: %{}, do: {unit.key, unit}

        check =
          case Work.check(op.source_digest, scope, units, answer) do
            :ok -> []
            {:error, problems} -> Enum.map(problems, &work_problem(&1, units))
          end

        names = Map.new(units, &{&1.key, &1.label})

        check ++
          answered_before(op, proposal, names) ++
          translated_texts(op.texts, by_key) ++
          translated_fields(op, schema, actor, check, names) ++ translated_links(op.texts)

      {:error, problem} ->
        [problem]
    end
  end

  defp translate_work(%Translate{target: {:new, _} = target}, proposal, actor) do
    case translation(proposal.operations, target) do
      %CreateTranslation{source: {schema, source_id}, language: language} ->
        with :ok <- readable_source(schema, source_id, actor),
             {:ok, %{units: units}} <- Work.new_translation_units(schema, source_id) do
          {:ok, schema, %{type: to_string(schema), id: {:new, source_id}, language: language}, units}
        else
          {:error, %{code: _} = problem} -> {:error, problem}
          {:error, _} -> {:error, translation_unavailable()}
        end

      nil ->
        {:error,
         problem(
           :unknown_target,
           dgettext(
             "content_proposals",
             "translate names {\"new\": ref}, and no create_translation in this proposal has that ref. Name the translation a create_translation creates, or an existing translation."
           )
         )}
    end
  end

  defp translate_work(%Translate{target: {schema, id}}, _proposal, actor) do
    case Work.translation_units(schema, id) do
      {:ok, work} ->
        with :ok <- readable_source(schema, work.source_id, actor),
             do: {:ok, schema, %{type: to_string(schema), id: id, language: work.language}, work.units}

      {:error, reason} ->
        {:error, not_a_translation(reason)}
    end
  end

  defp readable_source(schema, source_id, actor) do
    case Error.protect(fn -> load!({schema, source_id}, actor, action: :read) end) do
      {:ok, _source} -> :ok
      {:error, _} -> {:error, translation_unavailable()}
    end
  end

  defp translation_unavailable,
    do:
      problem(
        :unknown_target,
        dgettext("content_proposals", "The source of this translation is not available to you.")
      )

  defp not_a_translation(:not_synchronized),
    do:
      problem(
        :not_translation,
        dgettext(
          "content_proposals",
          "This content type is not synchronized: it has no translation work. Change its text with set_fields and set_block_text."
        )
      )

  defp not_a_translation(:source),
    do:
      problem(
        :not_translation,
        dgettext(
          "content_proposals",
          "This entry is its group's source. translate fills in one of its translations: name the translation."
        )
      )

  defp not_a_translation(:independent),
    do:
      problem(
        :not_translation,
        dgettext(
          "content_proposals",
          "This translation is independent: it no longer follows its source and has no translation work. Change its text with set_fields and set_block_text."
        )
      )

  defp not_a_translation(_reason),
    do:
      problem(
        :not_translation,
        dgettext(
          "content_proposals",
          "This entry is not a synchronized translation, so it has no translation work to answer."
        )
      )

  @work_codes %{
    "stale" => :stale,
    "source_changed" => :source_changed,
    "extra" => :extra_key,
    "missing" => :missing_key,
    "duplicate" => :duplicate_key,
    "malformed" => :malformed,
    "not_text" => :not_text,
    "blank" => :blank_text,
    "html_changed" => :html_changed,
    "placeholders_changed" => :placeholders_changed
  }

  # A problem of `Work.check/4`, in the admin's language, naming its unit by
  # its label; the key is the problem's `key`.
  defp work_problem(%{key: key, code: code}, units) do
    unit = Enum.find(units, &(&1.key == key))
    name = (unit && unit.label) || key
    key_problem(Map.fetch!(@work_codes, code), key, work_message(code, name, unit))
  end

  defp work_message("stale", _name, _unit),
    do:
      dgettext(
        "content_proposals",
        "This source_digest is not one translation_work gave for this entry and language. Read the work again."
      )

  defp work_message("malformed", _name, _unit),
    do: dgettext("content_proposals", "texts must be an object of {key: translation}, and reviewed a list of keys.")

  defp work_message("source_changed", name, _unit),
    do:
      dgettext(
        "content_proposals",
        "The source text of %{name} changed since it was read, or it no longer needs translation. Read translation_work again.",
        name: name
      )

  defp work_message("extra", name, _unit),
    do:
      dgettext(
        "content_proposals",
        "%{name} is not a unit of the batch this source_digest was read with. Leave it out.",
        name: name
      )

  defp work_message("missing", name, _unit),
    do:
      dgettext(
        "content_proposals",
        "%{name} is not answered. Give its translation in texts, or list it in reviewed to keep it.",
        name: name
      )

  defp work_message("duplicate", name, _unit),
    do:
      dgettext(
        "content_proposals",
        "%{name} is answered more than once. Give a text in texts or list it in reviewed, not both.",
        name: name
      )

  defp work_message("not_text", name, _unit),
    do: dgettext("content_proposals", "The translation of %{name} must be a string.", name: name)

  defp work_message("blank", name, _unit),
    do:
      dgettext(
        "content_proposals",
        "The translation of %{name} is empty. Translate the text, or list its key in reviewed.",
        name: name
      )

  defp work_message("html_changed", name, unit),
    do:
      dgettext(
        "content_proposals",
        "The translation of %{name} changed its HTML tags or attributes. Keep every tag of the source, in order, with its attributes exactly as they are: %{tags}",
        name: name,
        tags: Enum.join(Work.html_tags(unit_source(unit)), " ")
      )

  defp work_message("placeholders_changed", name, unit) do
    case Work.placeholders(unit_source(unit)) do
      [] ->
        dgettext(
          "content_proposals",
          "The translation of %{name} has template placeholders, and its source has none. Leave them out.",
          name: name
        )

      placeholders ->
        dgettext(
          "content_proposals",
          "The translation of %{name} changed its template placeholders. Keep each exactly as the source has it: %{placeholders}",
          name: name,
          placeholders: Enum.join(Enum.sort(placeholders), " ")
        )
    end
  end

  defp unit_source(%{source: source}) when is_binary(source), do: source
  defp unit_source(_unit), do: ""

  # The message names the unit; its key is the problem's `key`.
  defp key_problem(code, nil, message), do: problem(code, message)
  defp key_problem(code, key, message), do: code |> problem(message) |> Map.put(:key, key)

  # A key is answered once across the proposal's batches.
  defp answered_before(%Translate{target: target} = op, proposal, names) do
    earlier =
      proposal.operations
      |> Enum.take_while(&(&1 !== op))
      |> Enum.flat_map(fn
        %Translate{target: ^target} = earlier -> answered_keys(earlier)
        _ -> []
      end)
      |> MapSet.new()

    for key <- Enum.uniq(answered_keys(op)), MapSet.member?(earlier, key) do
      key_problem(
        :duplicate_key,
        key,
        dgettext("content_proposals", "An earlier translate operation in this proposal already answers %{name}.",
          name: names[key] || key
        )
      )
    end
  end

  defp answered_keys(%Translate{texts: texts, reviewed: reviewed}) do
    keys = if is_map(texts), do: Map.keys(texts), else: []
    reviewed = if is_list(reviewed), do: Enum.filter(reviewed, &is_binary/1), else: []
    Enum.filter(keys, &is_binary/1) ++ reviewed
  end

  # The proposal's own rules for a text, by the unit's format, as
  # `set_block_text` and `set_fields` apply them. A translation keeps the
  # source's template placeholders (`Work.check/4` requires them), so those
  # are taken out before a `{` is refused; any other is refused as anywhere.
  defp translated_texts(texts, units) when is_map(texts) do
    for {key, text} <- texts,
        is_binary(text),
        %{} = unit <- [units[key]],
        message = translated_text_problem(unit, text),
        do: key_problem(:unsafe_text, key, message)
  end

  defp translated_texts(_texts, _units), do: []

  defp translated_text_problem(unit, text) do
    rest = Enum.reduce(Work.placeholders(unit.source || ""), text, &String.replace(&2, &1, ""))
    name = Map.get(unit, :label) || unit.key

    if placeholders_moved?(unit, text),
      do: placeholder_place_problem(name),
      else: format_problem(unit, rest, name)
  end

  defp format_problem(unit, rest, name) do
    cond do
      unit.format == "html" -> rich_text_problem(rest, name)
      unit.format == "markdown" -> rich_text_problem(checked_text("markdown", rest), name)
      String.ends_with?(unit.key, "/url") -> address_problem(rest, name)
      # A plain text whose source holds markup keeps it (`Work.check/4`)
      Regex.match?(~r/<[a-z\/][^>]*>/i, unit.source || "") -> rich_text_problem(rest, name)
      true -> plain_text_problem(rest, name)
    end
  end

  # A placeholder the source has is taken out before a text is checked, so
  # it must stay where the source has it: as text inside the same tags, or
  # in the same attribute of the same tag, and never put into an attribute
  # or a tag of the translation's own, where its output would become markup
  # or an address the check never saw. Places are read from the parsed
  # markup, as browsers read it; attribute values and other attributes do
  # not count, so an address or an alt text may be translated around it.
  @placeholder_pattern ~r/\{\{.*?\}\}|\{%.*?%\}|<%.*?%>/su
  @placeholder_marker ~r/zqbrandoplaceholder(\d+)zq/

  defp placeholders_moved?(unit, text) do
    source = unit.source || ""

    case Work.placeholders(source) do
      [] ->
        false

      _ ->
        placeholders = Enum.uniq(Work.placeholders(source) ++ Work.placeholders(text))
        places(unit, source, placeholders) != places(unit, text, placeholders)
    end
  end

  # Each placeholder of `text` with its place, sorted: the placeholders are
  # replaced by markers that survive parsing, and Markdown is rendered.
  defp places(unit, text, placeholders) do
    markers = placeholders |> Enum.with_index() |> Map.new(fn {p, i} -> {p, "zqbrandoplaceholder#{i}zq"} end)
    names = placeholders |> Enum.with_index() |> Map.new(fn {p, i} -> {Integer.to_string(i), p} end)

    @placeholder_pattern
    |> Regex.replace(text, &Map.fetch!(markers, &1))
    |> placed(unit)
    |> Brando.HTML.Tree.parse_fragment()
    |> Enum.flat_map(&node_places(&1, []))
    |> Enum.map(fn {index, place} -> {Map.fetch!(names, index), place} end)
    |> Enum.sort()
  end

  defp placed(text, %{format: "markdown"}), do: checked_text("markdown", text)
  defp placed(text, _unit), do: text

  defp node_places(text, ancestors) when is_binary(text),
    do: for(index <- marker_indexes(text), do: {index, {:text, ancestors}})

  defp node_places({:comment, text}, ancestors),
    do: for(index <- marker_indexes(text), do: {index, {:comment, ancestors}})

  defp node_places({tag, attributes, children}, ancestors) do
    in_attributes =
      for {name, value} <- attributes, index <- marker_indexes(name <> " " <> value), do: {index, {:attribute, tag, name}}

    in_attributes ++ Enum.flat_map(children, &node_places(&1, [tag | ancestors]))
  end

  defp node_places(_node, _ancestors), do: []

  defp marker_indexes(text),
    do: @placeholder_marker |> Regex.scan(text, capture: :all_but_first) |> List.flatten()

  defp placeholder_place_problem(name),
    do:
      dgettext(
        "content_proposals",
        "%{name} puts a template placeholder in markup the source does not have around it. Keep each placeholder as text where the source has it, inside the same tags.",
        name: name
      )

  # A field's text: the field is not one a proposal may write, or one the
  # forms lock, as `set_fields` refuses them. `translation_work` leaves such
  # a unit out of the batch, so it is refused as extra already; this refuses
  # a token that holds it anyway.
  defp translated_fields(op, schema, actor, check, names) do
    extra = for %{code: :extra_key, key: key} <- check, do: key

    for key <- Enum.uniq(answered_keys(op)), key not in extra, locked_unit?(schema, key, actor) do
      key_problem(
        :protected_field,
        key,
        dgettext("content_proposals", "A proposal cannot change %{name}.", name: names[key] || key)
      )
    end
  end

  @doc """
  Whether a translation unit `key` of `schema` is in a field a proposal by
  `actor` may not write: one no proposal writes, or one the forms lock for
  anyone but a superuser. Text in blocks is never locked.
  """
  @spec locked_unit?(module(), String.t(), term()) :: boolean()
  def locked_unit?(schema, key, actor) do
    blocks = Enum.map(schema.__blocks_fields__(), &"entry_#{&1.name}")
    field = key |> String.split("/", parts: 2) |> hd()
    fields = %{field => nil}

    field not in blocks and protected_fields(fields, schema) ++ locked_fields(fields, schema, actor) != []
  end

  defp translated_links(texts) when is_map(texts), do: link_problems(%{texts: texts})
  defp translated_links(_texts), do: []

  # The source is read as the actor may read it.
  defp source_problems(op, source, proposal, actor) do
    case Error.protect(fn -> load!(source, actor, action: :read) end) do
      {:ok, source} -> translation_problems(op, source, proposal, actor)
      {:error, message} -> [problem(:unknown_target, message)]
    end
  end

  defp duplicate_ref?(op, proposal) do
    Enum.count(proposal.operations, fn
      %type{ref: ref} when type in [CreateEntry, CreateTranslation] -> ref == op.ref
      _ -> false
    end) > 1
  end

  # What the editor's Create translation checks, in the listing and the form,
  # and `Brando.Translations.create_target/5` under them.
  defp translation_problems(op, %schema{} = source, proposal, actor) do
    cond do
      Boundary.authorize(actor, :create, schema) != :ok or Boundary.authorize(actor, :duplicate, source) != :ok ->
        [
          problem(
            :forbidden,
            dgettext("content_proposals", "You do not have permission to create a translation of this entry.")
          )
        ]

      # The apply reads the new translation back as the actor may edit it,
      # and translating it is editing it.
      Boundary.authorize(actor, :update, schema) != :ok ->
        [
          problem(
            :forbidden,
            dgettext(
              "content_proposals",
              "Creating a translation takes permission to edit %{name} entries as well, which you do not have.",
              name: Codec.content_type(schema)
            )
          )
        ]

      true ->
        language_problems(op, source, proposal, actor)
    end
  end

  defp language_problems(%CreateTranslation{language: language} = op, %schema{} = source, proposal, actor) do
    member = Translations.get_member(schema, source.id)
    earlier = Enum.take_while(proposal.operations, &(&1 !== op))

    cond do
      match?(%{role: :target}, member) ->
        [not_source(schema, member, actor)]

      language not in Enum.map(entry_languages(schema), & &1.code) ->
        [
          problem(
            :unknown_language,
            dgettext("content_proposals", "%{language} is not one of the site's languages for %{name} entries.",
              language: inspect(language),
              name: Codec.content_type(schema)
            )
          )
        ]

      language == to_string(source.language) ->
        [problem(:same_language, dgettext("content_proposals", "The source is already in this language."))]

      language in group_languages(schema, source, member) ->
        [
          problem(
            :language_exists,
            dgettext(
              "content_proposals",
              "The source already has a version in this language. Change that version instead."
            )
          )
        ]

      Enum.any?(earlier, &same_translation?(&1, op, member)) ->
        [
          problem(
            :language_exists,
            dgettext("content_proposals", "An earlier operation in this proposal already creates this version.")
          )
        ]

      true ->
        []
    end
  end

  # Named a translation, the client is told which entry the group's source is.
  defp not_source(schema, member, actor) do
    source =
      Enum.find_value(Translations.list_members(member.group_id), fn
        %{role: :source, entry_id: id} -> id
        _ -> nil
      end)

    readable? = source && readable?(schema, source, actor)

    message =
      if readable?,
        do:
          dgettext(
            "content_proposals",
            "This entry is a translation. Create translations from its group's source, %{source}.",
            source: Jason.encode!(Codec.target({schema, source}))
          ),
        else: dgettext("content_proposals", "This entry is a translation. Create translations from its group's source.")

    problem(:not_source, message)
  end

  # The languages the source's group holds, and those of the independent
  # versions it is linked to as alternates.
  defp group_languages(schema, source, member) do
    members = if member, do: Enum.map(Translations.list_members(member.group_id), & &1.language), else: []
    members ++ Translations.alternate_languages(schema, source.id)
  end

  defp same_translation?(%CreateTranslation{source: {schema, id}, language: language}, op, member) do
    {op_schema, op_id} = op.source

    schema == op_schema and language == op.language and
      (id == op_id or
         (member != nil and
            match?(%{group_id: group_id} when group_id == member.group_id, Translations.get_member(schema, id))))
  end

  defp same_translation?(_earlier, _op, _member), do: false

  defp saved_tree(target, field, proposal) do
    case Map.get(proposal.targets, target) do
      # A field the entry lacks is reported by the operation's own check.
      %{} = entry -> entry |> entry_blocks(field) |> BlockTree.from_saved()
      _ -> %BlockTree{}
    end
  end

  # The field name comes from the tool unchecked, so it is compared as a
  # string: an unknown one must not become an atom.
  defp entry_blocks(entry, field) do
    name = "entry_#{field}"
    entry |> Map.to_list() |> Enum.find_value([], fn {key, blocks} -> Atom.to_string(key) == name && blocks end)
  end

  defp check_block(%InsertBlock{} = op, schema, tree, actor, proposal) do
    with :ok <- new_uid(op.uid, tree, actor),
         :ok <- new_ref_uids(op.ref_uids),
         {:ok, module, type} <- insertable(op, schema, tree),
         :ok <- sibling_placement(op.placement, op.parent, op.uid, tree) do
      node = %{
        uid: op.uid,
        parent: op.parent,
        type: type,
        module: op.module,
        multi: !!module.multi,
        slot_module_set: nil
      }

      problems =
        values(op.values, module.vars, actor) ++
          Enum.flat_map(op.texts, fn {name, text} -> text(name, text, module) end) ++
          Enum.flat_map(op.media, fn {name, asset} -> media(name, asset, module, actor) end) ++
          Enum.flat_map(op.configs, fn {name, config} -> config(name, config, module) end) ++
          draft_dependencies(op.values, proposal)

      {problems, BlockTree.put(tree, node, op.parent, op.placement)}
    else
      # Text is checked whatever else is wrong, so it is reported in the same
      # round. An insert that stops at `parent_failed` is not checked at all.
      {:error, problem} -> {[problem | inserted_unsafe_text(op, actor)], tree}
    end
  end

  defp check_block(%MoveBlock{} = op, schema, tree, _actor, _proposal) do
    with {:ok, node} <- structural_block(tree, op.block_uid),
         {:ok, parent} <- destination(op.placement, node, tree, :move),
         :ok <- movable(node, parent, schema, op.field, tree) do
      {[], BlockTree.move(tree, op.block_uid, parent, op.placement)}
    else
      {:error, problem} -> {[problem], tree}
    end
  end

  # A copy to another entry or field is checked against that field, with the
  # saved original.
  defp check_block(%CopyBlock{to_target: to}, _schema, tree, _actor, _proposal) when not is_nil(to),
    do: {[], tree}

  # A copy may sit next to its original, but not inside it.
  defp check_block(%CopyBlock{} = op, schema, tree, actor, _proposal) do
    with {:ok, node} <- structural_block(tree, op.block_uid),
         :ok <- new_uid(op.uid, tree, actor),
         {:ok, parent} <- destination(op.placement, node, tree, :copy),
         :ok <- movable(node, parent, schema, op.field, tree) do
      {[], BlockTree.copy(tree, op.block_uid, op.uid, parent, op.placement)}
    else
      {:error, problem} -> {[problem], tree}
    end
  end

  defp check_block(%SetBlockTable{} = op, _schema, tree, actor, proposal) do
    problems =
      with {:ok, module} <- module_block(tree, op.block_uid),
           [_ | _] = vars <- table_vars(module) do
        rows_problems(op.rows, vars, actor, proposal)
      else
        {:error, problem} -> [problem]
        [] -> [problem(:unsupported_value, dgettext("content_proposals", "This module has no table."))]
      end

    {problems, tree}
  end

  defp check_block(%SetBlockSelection{identifiers: ids} = op, _schema, tree, _actor, proposal) do
    problems =
      case module_block(tree, op.block_uid) do
        {:ok, %{datasource: true, datasource_type: type} = module} when type in [:selection, :single] ->
          available = module |> selection_options(language(op.target, proposal)) |> MapSet.new(& &1.id)

          cond do
            type == :single and length(ids) > 1 ->
              [problem(:unsupported_value, dgettext("content_proposals", "This block shows one entry."))]

            Enum.all?(ids, &MapSet.member?(available, &1)) ->
              []

            true ->
              [
                problem(
                  :unsupported_value,
                  dgettext("content_proposals", "Choose entries from the block's options (list_selection_options).")
                )
              ]
          end

        {:ok, _module} ->
          [problem(:unsupported_value, dgettext("content_proposals", "This block does not show chosen entries."))]

        {:error, problem} ->
          [problem]
      end

    {problems, tree}
  end

  defp check_block(%SetBlockDetails{} = op, _schema, tree, _actor, _proposal) do
    problems =
      case structural_block(tree, op.block_uid) do
        {:ok, _node} -> anchor(op.anchor) ++ description(op.description)
        {:error, problem} -> [problem]
      end

    {problems, tree}
  end

  defp check_block(%SetBlockActive{ref: nil} = op, _schema, tree, _actor, _proposal) do
    case structural_block(tree, op.block_uid) do
      {:ok, _node} -> {[], tree}
      {:error, problem} -> {[problem], tree}
    end
  end

  defp check_block(%DeleteBlock{} = op, _schema, tree, _actor, _proposal) do
    case structural_block(tree, op.block_uid) do
      {:ok, _node} -> {[], BlockTree.delete(tree, op.block_uid)}
      {:error, problem} -> {[problem], tree}
    end
  end

  defp check_block(%{block_uid: uid} = op, _schema, tree, actor, proposal) do
    problems =
      case module_block(tree, uid) do
        {:ok, module} ->
          case op do
            %SetBlockMedia{ref: name, asset: asset} -> media(to_string(name), asset, module, actor)
            %SetBlockValues{values: values} -> values(values, module.vars, actor) ++ draft_dependencies(values, proposal)
            %SetBlockText{ref: name, text: text} -> text(to_string(name), text, module)
            %SetBlockActive{ref: name} -> ref_exists(name, module)
            %SetRefConfig{ref: name, config: config} -> config(name, config, module)
          end

        {:error, problem} ->
          [problem]
      end

    {problems, tree}
  end

  defp inserted_unsafe_text(op, actor) do
    case fetch_module(op.module) do
      %{} = module ->
        (values(op.values, module.vars, actor) ++
           Enum.flat_map(op.texts, fn {name, text} -> text(name, text, module) end) ++
           Enum.flat_map(op.configs, fn {name, config} -> config(name, config, module) end))
        |> Enum.filter(&(&1.code == :unsafe_text))

      _ ->
        []
    end
  end

  defp unknown_block,
    do:
      problem(
        :unknown_block,
        dgettext("content_proposals", "This block is not in the field. Use a uid from entry_outline.")
      )

  defp module_block(tree, uid) do
    with %{module: {_, _} = reference, type: type} when type in [:module, :module_entry] <- BlockTree.fetch(tree, uid),
         %{} = module <- fetch_module(reference) do
      {:ok, module}
    else
      nil -> {:error, unknown_block()}
      _ -> {:error, problem(:unknown_block, dgettext("content_proposals", "This block is not built from a module."))}
    end
  end

  # Slots are the internal collections of a module's refs; their order and
  # existence belong to the module.
  defp structural_block(tree, uid) do
    case BlockTree.fetch(tree, uid) do
      nil ->
        {:error, unknown_block()}

      %{type: :slot} ->
        {:error, problem(:unknown_block, dgettext("content_proposals", "A slot cannot be moved or deleted."))}

      node ->
        {:ok, node}
    end
  end

  defp config(name, config, module) do
    case Enum.find(module.refs || [], &(&1.name == name)) do
      nil ->
        ref_exists(name, module)

      definition ->
        Enum.map(RefConfig.problems(name, definition, config), &problem(:unsupported_value, &1)) ++
          Enum.flat_map(config, fn {key, value} -> setting_problems(to_string(key), value) end)
    end
  end

  # Settings are rendered into attributes (a heading's class, id and link)
  # and captions. A caption's title and credits take safe rich text, a link
  # an address, a class or id no quotes, and any other text no markup.
  defp setting_problems(_key, ""), do: []

  defp setting_problems(key, value) when is_binary(value) do
    cond do
      key in ~w(title credits) -> unsafe(rich_text_problem(value, key))
      key in ~w(link poster) -> unsafe(address_problem(value, key))
      key == "id" or String.ends_with?(key, "class") -> unsafe(token_problem(value, key))
      true -> unsafe(plain_text_problem(value, key))
    end
  end

  defp setting_problems(_key, _value), do: []

  # An image, video or file field takes media of its own kind, from the
  # library. The value is saved as the asset's id.
  defp list_fields(fields, schema, actor),
    do: for({code, message} <- EntryFields.problems(schema, fields, actor), do: problem(code, message))

  # A link to an entry that could not be resolved to its page.
  defp link_problems(op) do
    texts =
      [Map.get(op, :text)] ++
        Map.values(Map.get(op, :texts) || %{}) ++
        Map.values(Map.get(op, :fields) || %{}) ++ Map.values(Map.get(op, :values) || %{})

    if Enum.any?(texts, &EntryLinks.unresolved?/1),
      do: [
        problem(
          :unknown_target,
          dgettext("content_proposals", "A link points to an entry that was not found or has no page yet.")
        )
      ],
      else: []
  end

  defp asset_fields(fields, schema, actor) do
    for {name, {kind, id}} <- fields, kind in [:image, :video, :file, :gallery] do
      case asset_field(schema, name) do
        ^kind when kind != :gallery -> assets({kind, id}, [], name, actor)
        _ -> [wrong_media(name)]
      end
    end
    |> List.flatten()
  end

  defp asset_field(schema, name) do
    Enum.find_value(Brando.Blueprint.Assets.__assets__(schema), fn
      %{name: asset, type: type} -> if "#{asset}_id" == name, do: type
    end)
  end

  defp rows_problems(rows, vars, actor, proposal) do
    galleries? = Enum.any?(rows, fn row -> Enum.any?(row, &match?({_, {:gallery, _}}, &1)) end)

    if galleries?,
      do: [problem(:unsupported_value, dgettext("content_proposals", "Table rows cannot hold galleries."))],
      else:
        rows
        |> Enum.flat_map(&(values(&1, vars, actor) ++ draft_dependencies(&1, proposal)))
        |> Enum.uniq()
  end

  @doc "The variables each row of `module`'s table has, from its table template."
  @spec table_vars(map()) :: [Brando.Content.Var.t()]
  def table_vars(%{table_template_id: id}) when is_integer(id) do
    case Repo.one(
           from(t in Brando.Content.TableTemplate,
             where: t.id == ^id,
             preload: [vars: ^from(v in Brando.Content.Var, order_by: [asc: v.sequence, asc: v.id])]
           )
         ) do
      %{vars: vars} -> vars
      nil -> []
    end
  end

  def table_vars(_module), do: []

  @doc """
  The identifiers a selection datasource block can show, as its datasource
  lists them for `language` — the same options the block editor offers.
  """
  @spec selection_options(map(), String.t() | atom() | nil) :: [Brando.Content.Identifier.t()]
  def selection_options(%{datasource_module: ds_module, datasource_query: query} = module, language)
      when is_binary(ds_module) do
    vars = Enum.map(module.vars || [], &Changeset.change/1)

    case Brando.Datasource.list_results(
           Brando.Datasource.Registry.module!(ds_module),
           query,
           vars,
           language && to_string(language),
           datasource_type(module)
         ) do
      {:ok, identifiers} when is_list(identifiers) -> identifiers
      _ -> []
    end
  rescue
    _ -> []
  end

  def selection_options(_module, _language), do: []

  # A selection or a single datasource lists its options; the module names
  # which one it uses, by type and key.
  defp datasource_type(%{datasource_type: type}) when type in [:selection, :single], do: type
  defp datasource_type(%{datasource_type: type}) when type in ["selection", "single"], do: String.to_existing_atom(type)
  defp datasource_type(_module), do: :*

  defp language({:new, ref}, proposal) do
    case Enum.find(proposal.operations, &match?(%CreateEntry{ref: ^ref}, &1)) do
      %{schema: schema, fields: fields} -> new_entry_fields(schema, fields)["language"]
      nil -> nil
    end
  end

  defp language(target, proposal), do: proposal.targets |> Map.get(target) |> then(&(&1 && Map.get(&1, :language)))

  defp ref_exists(name, module) do
    if Enum.any?(module.refs || [], &(&1.name == name)),
      do: [],
      else: [problem(:unknown_ref, dgettext("content_proposals", "The module has no ref %{name}.", name: name))]
  end

  # Where a move puts the block: among its siblings, next to another block —
  # under that block's parent — or at the end of a block's children. A block
  # cannot go inside itself.
  defp destination(:append, node, _tree, _kind), do: {:ok, node.parent}

  defp destination({side, anchor}, node, tree, kind) when side in [:before, :after, :into] do
    case BlockTree.fetch(tree, anchor) do
      nil ->
        {:error, unknown_placement()}

      anchor_node ->
        parent = if side == :into, do: anchor, else: anchor_node.parent
        next_to_self? = kind == :move and BlockTree.within?(tree, node.uid, anchor)

        if next_to_self? or (parent && BlockTree.within?(tree, node.uid, parent)),
          do: {:error, problem(:unknown_placement, dgettext("content_proposals", "A block cannot move inside itself."))},
          else: {:ok, parent}
    end
  end

  defp destination(_placement, _node, _tree, _kind), do: {:error, unknown_placement()}

  # An anchor is the fragment a link jumps to: a letter, then letters,
  # digits, dashes and underscores.
  defp anchor(nil), do: []
  defp anchor(""), do: []

  defp anchor(anchor) do
    if anchor =~ ~r/^[A-Za-z][A-Za-z0-9_-]{0,63}$/,
      do: [],
      else: [
        problem(
          :unsupported_value,
          dgettext("content_proposals", "An anchor starts with a letter and holds letters, digits, - and _.")
        )
      ]
  end

  defp description(description) when is_binary(description) and byte_size(description) > 255,
    do: [problem(:unsupported_value, dgettext("content_proposals", "A block description is at most 255 characters."))]

  defp description(_), do: []

  defp unknown_placement,
    do: problem(:unknown_placement, dgettext("content_proposals", "The block to place it next to is not in the field."))

  # A block moving to another parent must be one the new parent takes.
  defp movable(%{parent: parent}, parent, _schema, _field, _tree), do: :ok

  defp movable(%{module: {_, _} = reference, type: type}, parent, schema, field, tree)
       when type in [:module, :module_entry] do
    with {:ok, _module, _type} <- placeable(reference, parent, schema, field, tree), do: :ok
  end

  defp movable(_node, _parent, _schema, _field, _tree),
    do:
      {:error,
       problem(
         :unknown_placement,
         dgettext("content_proposals", "Only blocks built from a module can move to another parent.")
       )}

  defp new_uid(uid, tree, actor) do
    cond do
      is_binary(uid) and byte_size(uid) > @new_uid_bytes ->
        {:error,
         problem(
           :invalid_uid,
           dgettext("content_proposals", "A uid can be at most %{count} characters long.", count: @new_uid_bytes)
         )}

      not Content.Block.valid_uid?(uid) ->
        {:error, invalid_uid()}

      true ->
        saved = Repo.one(from(b in Content.Block, where: b.uid == ^uid, select: b.id, limit: 1))

        cond do
          BlockTree.fetch(tree, uid) != nil -> {:error, duplicate_uid(uid, if(saved, do: :field, else: :proposal))}
          saved -> {:error, duplicate_uid(uid, {:entry, entry_label(saved, actor)})}
          true -> :ok
        end
    end
  end

  # Where the uid is taken, so it can be changed: in this proposal or field,
  # or in another entry, named only when the actor may read it.
  defp duplicate_uid(uid, where) do
    taken =
      case where do
        :proposal ->
          dgettext("content_proposals", "The uid `%{uid}` is already used by another block in this proposal.", uid: uid)

        :field ->
          dgettext("content_proposals", "The uid `%{uid}` is already used by another block in this field.", uid: uid)

        {:entry, nil} ->
          dgettext("content_proposals", "The uid `%{uid}` is already used by a block in another entry.", uid: uid)

        {:entry, entry} ->
          dgettext("content_proposals", "The uid `%{uid}` is already used by a block in %{entry}.",
            uid: uid,
            entry: entry
          )
      end

    advice =
      dgettext(
        "content_proposals",
        "Uids are unique across the site; prefix yours, for example with the entry's ref or slug."
      )

    problem(:duplicate_uid, taken <> " " <> advice)
  end

  defp entry_label(block_id, actor) do
    with %{^block_id => [{schema, id} | _]} <- Content.BlockReferences.list_entries_for_block_ids([block_id]),
         true <- readable?(schema, id, actor) do
      dgettext("content_proposals", "%{content_type} #%{id}", content_type: Brando.Blueprint.get_singular(schema), id: id)
    else
      _ -> nil
    end
  end

  defp readable?(schema, id, actor) do
    query = Catalog.scoped_query(from(e in schema, where: e.id == ^id), schema, actor, :read)

    case Repo.one(query) do
      nil -> false
      entry -> Boundary.authorize(actor, :read, entry) == :ok
    end
  end

  defp new_ref_uids(ref_uids) do
    if ref_uids |> Map.values() |> Enum.all?(&Content.Block.valid_uid?/1),
      do: :ok,
      else: {:error, invalid_uid()}
  end

  defp invalid_uid do
    problem(
      :invalid_uid,
      dgettext("content_proposals", "A uid can only hold letters, digits, - and _, and cannot end with -.")
    )
  end

  # Which module a block may be built from depends on where it goes: the
  # field's allowed modules at the root or in a container, a multi module's
  # own entries, or a slot's module set.
  defp insertable(%InsertBlock{} = op, schema, tree), do: placeable(op.module, op.parent, schema, op.field, tree)

  defp placeable(reference, nil, schema, field, _tree) do
    with {:ok, module} <- allowed_module(reference, schema, field), do: {:ok, module, :module}
  end

  defp placeable(reference, parent, schema, field, tree) do
    case {BlockTree.fetch(tree, parent), fetch_module(reference)} do
      {nil, _} ->
        {:error, unknown_block()}

      {_, nil} ->
        {:error, problem(:unknown_module, dgettext("content_proposals", "This module does not exist."))}

      {%{type: :container}, _module} ->
        with {:ok, module} <- allowed_module(reference, schema, field), do: {:ok, module, :module}

      {parent, module} ->
        child_module(parent, module, reference)
    end
  end

  defp child_module(%{multi: true, module: {origin, id}}, module, reference) do
    if module.parent_id == id and match?({^origin, _}, reference),
      do: {:ok, module, :module_entry},
      else:
        {:error,
         problem(
           :module_not_allowed,
           dgettext("content_proposals", "This module is not an entry of the block it goes into.")
         )}
  end

  defp child_module(%{type: :slot, slot_module_set: set}, module, _reference) do
    if BlockSlots.suitable_module?(module) and Enum.any?(BlockSlots.modules(set), &(&1.id == module.id)),
      do: {:ok, module, :module},
      else:
        {:error,
         problem(:module_not_allowed, dgettext("content_proposals", "This module is not available in this slot."))}
  end

  defp child_module(_parent, _module, _reference),
    do: {:error, problem(:not_a_parent, dgettext("content_proposals", "This block cannot hold other blocks."))}

  defp sibling_placement(:append, _parent, _uid, _tree), do: :ok

  defp sibling_placement({side, anchor}, parent, uid, tree) when side in [:before, :after] and anchor != uid do
    if BlockTree.sibling?(tree, parent, anchor),
      do: :ok,
      else:
        {:error,
         problem(
           :unknown_placement,
           dgettext("content_proposals", "The block to place it next to must have the same parent.")
         )}
  end

  defp sibling_placement(_placement, _parent, _uid, _tree),
    do: {:error, problem(:unknown_placement, dgettext("content_proposals", "Unknown placement."))}

  defp protected_fields(fields, schema) do
    blocks = Enum.flat_map(schema.__blocks_fields__(), &[to_string(&1.name), "entry_#{&1.name}", "rendered_#{&1.name}"])

    for key <- Map.keys(fields), key in @protected_fields or key in blocks, do: protected_field(key)
  end

  defp protected_field(key) do
    problem(
      :protected_field,
      dgettext("content_proposals", "%{field} cannot be changed by a proposal.", field: key)
    )
  end

  # A field the forms lock for anyone but a superuser, as a transfer bundle
  # holds them (`LockedFields.held_keys/2`). The role is the author's: only they
  # approve and apply a proposal, and it is read again each time.
  defp locked_fields(fields, schema, actor) do
    held = schema |> LockedFields.held_keys(nil) |> Enum.map(&to_string/1)

    case Enum.filter(Map.keys(fields), &(&1 in held)) do
      [] ->
        []

      locked ->
        if Boundary.superuser?(actor), do: [], else: Enum.map(locked, &protected_field/1)
    end
  end

  # Templates output entry fields as they are, so each text in a field — a
  # plain value, or one in a translation map, a list or a subform row — takes
  # safe rich text.
  defp text_fields(fields) do
    for {key, value} <- fields, text <- texts(value), reduce: [] do
      problems -> problems ++ unsafe(rich_text_problem(text, key))
    end
    |> Enum.uniq()
  end

  defp texts(value) when is_binary(value), do: [value]
  defp texts(value) when is_map(value) and not is_struct(value), do: value |> Map.values() |> Enum.flat_map(&texts/1)
  defp texts(value) when is_list(value), do: Enum.flat_map(value, &texts/1)
  defp texts(_value), do: []

  # An existing entry's status: a real one for its type, and publishing —
  # into or out of published — needs the publish permission.
  defp status_problems(status, _schema, _entry, _actor) when status == %{}, do: []

  defp status_problems(%{"status" => value}, schema, entry, actor) do
    new = if is_binary(value) or is_atom(value), do: to_string(value)
    old = entry && to_string(Map.get(entry, :status))

    cond do
      :status not in schema.__schema__(:fields) ->
        [problem(:protected_field, dgettext("content_proposals", "This content type has no status."))]

      new not in ~w(published draft disabled pending) ->
        [
          problem(
            :unsupported_value,
            dgettext("content_proposals", "The status is published, draft, disabled or pending.")
          )
        ]

      publish_forbidden?(new, old, schema, actor) ->
        [problem(:forbidden, dgettext("content_proposals", "You cannot publish or unpublish this content type."))]

      true ->
        []
    end
  end

  defp publish_forbidden?(new, old, schema, actor) do
    "published" in [new, old] and new != old and
      Brando.Authorization.Boundary.authorize(actor, :publish, schema) != :ok
  end

  defp draft_dependencies(values, proposal) do
    for {_, value} <- values,
        {:new, ref} <- [link_target(value)],
        Map.has_key?(proposal.targets, {:new, to_string(ref)}) do
      problem(
        :draft_dependency,
        dgettext(
          "content_proposals",
          "This links to a new entry, which is created as a draft. Its page will not be public until it is published."
        )
      )
    end
  end

  # Clearing a module's link text is changing it too.
  defp link_text_problems(%{link_allow_custom_text: false}, key, %{text: _}),
    do: [
      problem(:unsupported_value, dgettext("content_proposals", "%{key} shows the text the module gives it.", key: key))
    ]

  defp link_text_problems(_var, _key, %{text: ""}), do: []
  defp link_text_problems(_var, key, %{text: text}), do: unsafe(plain_text_problem(text, key))
  defp link_text_problems(_var, _key, _opts), do: []

  defp link_target({:link, target, _opts}), do: target
  defp link_target(value), do: value

  defp target_schema({:new, _} = target, proposal) do
    case Map.fetch(proposal.targets, target) do
      {:ok, schema} ->
        {:ok, schema}

      :error ->
        {:error, problem(:unknown_target, dgettext("content_proposals", "No entry is created with this reference."))}
    end
  end

  defp target_schema({schema, _}, _proposal), do: {:ok, schema}

  defp block_field(schema, field) do
    if Enum.any?(schema.__blocks_fields__(), &(to_string(&1.name) == field)),
      do: :ok,
      else: {:error, problem(:unknown_field, dgettext("content_proposals", "This content type has no such block field."))}
  end

  defp allowed_module(reference, schema, field) do
    module = fetch_module(reference)

    cond do
      is_nil(module) ->
        {:error, problem(:unknown_module, dgettext("content_proposals", "This module does not exist."))}

      module.parent_id || module_id(module) not in allowed_module_ids(schema, field, module) ->
        {:error,
         problem(:module_not_allowed, dgettext("content_proposals", "This module is not available in this block field."))}

      true ->
        {:ok, module}
    end
  end

  defp allowed_module_ids(schema, field, module) do
    case module_set(schema, field) do
      set when set in [nil, "", "all"] ->
        [module_id(module)]

      set ->
        case Content.get_module_set(%{matches: %{title: set}, preload: [module_set_modules: :module]}) do
          {:ok, set} -> Enum.map(set.module_set_modules, &module_id(&1.module))
          _ -> []
        end
    end
  end

  @doc """
  The module set of a block field: the one its form declares (`blocks :blocks,
  module_set: …`), else the one the site configures for it, for schemas it
  doesn't own (`config :brando, Brando.Pages.Page, module_sets: [blocks:
  "Page"]`). It limits the root modules the editor's picker offers; `nil`
  allows all.
  """
  @spec module_set(module(), String.t()) :: String.t() | nil
  def module_set(schema, field) do
    with %{blocks: inputs} <- schema.__form__(),
         %{opts: opts} <- Enum.find(inputs, &(to_string(&1.name) == field)),
         set when is_binary(set) <- opts[:module_set] || configured_module_set(schema, field) do
      set
    else
      _ -> nil
    end
  end

  @doc "The module set the site configures for `schema`'s block field `field`, or `nil`."
  @spec configured_module_set(module(), String.t() | atom()) :: String.t() | nil
  def configured_module_set(schema, field) do
    :brando
    |> Application.get_env(schema, [])
    |> Keyword.get(:module_sets, [])
    |> Enum.find_value(fn {name, set} -> if to_string(name) == to_string(field), do: set end)
  end

  defp module_id(module), do: {Map.get(module, :library_origin) || :local, module.id}

  defp values(values, vars, actor) do
    Enum.flat_map(values, fn {key, value} ->
      value_problems(Enum.find(vars || [], &(&1.key == key)), key, value, actor)
    end)
  end

  defp value_problems(nil, key, _value, _actor),
    do: [problem(:unknown_var, dgettext("content_proposals", "The module has no variable %{key}.", key: key))]

  # A link's text shows as it is, so it is plain text; a module can keep it
  # for itself (`link_allow_custom_text`).
  defp value_problems(%{type: :link} = var, key, {:link, target, opts}, actor) do
    target_problems = if target, do: value_problems(var, key, target, actor), else: []
    target_problems ++ link_text_problems(var, key, opts)
  end

  # A new entry is reported by `draft_dependencies/2`.
  defp value_problems(%{type: :link}, _key, {:new, _}, _actor), do: []

  defp value_problems(%{type: :link} = var, key, {:entry, schema, id}, actor) do
    allowed = var.link_identifier_schemas || []

    cond do
      allowed != [] and to_string(schema) not in allowed and inspect(schema) not in allowed ->
        [problem(:unsupported_value, dgettext("content_proposals", "%{key} cannot link to this content type.", key: key))]

      match?({:error, _}, Error.protect(fn -> Catalog.load!(schema, id, actor, :read) end)) ->
        [problem(:unknown_target, dgettext("content_proposals", "The entry to link to was not found."))]

      match?({:error, _}, Content.get_identifier(schema, %{id: id})) ->
        [problem(:unsupported_value, dgettext("content_proposals", "The entry to link to has no identifier yet."))]

      true ->
        []
    end
  end

  defp value_problems(%{type: kind} = var, key, {kind, _} = asset, actor) when kind in [:image, :video, :file, :gallery],
    do: assets(asset, gallery_types(var), key, actor)

  defp value_problems(%{type: type}, key, {kind, _id}, _actor)
       when type in [:image, :video, :file, :gallery] and kind in [:image, :video, :file, :gallery],
       do: [
         problem(:wrong_media_type, dgettext("content_proposals", "%{name} does not accept this media type.", name: key))
       ]

  # Templates output text values as they are: a string takes plain text, a
  # text or HTML value safe rich text, and a link an address.
  defp value_problems(%{type: :string}, key, value, _actor) when is_binary(value),
    do: unsafe(plain_text_problem(value, key))

  defp value_problems(%{type: type}, key, value, _actor) when type in [:text, :rich_text] and is_binary(value),
    do: unsafe(rich_text_problem(value, key))

  defp value_problems(%{type: :link}, key, value, _actor) when is_binary(value) and value != "",
    do: unsafe(address_problem(value, key))

  defp value_problems(var, key, value, _actor),
    do: if(settable?(var, value), do: [], else: [unsupported(var, key, value)])

  defp settable?(%{type: :boolean}, value), do: is_boolean(value)
  defp settable?(%{type: type}, value) when type in @text_vars, do: is_binary(value)
  defp settable?(%{type: :select, options: options}, value), do: Enum.any?(options || [], &(&1.value == value))

  defp settable?(%{type: :color}, value) when is_binary(value),
    do: value =~ ~r/^#([[:xdigit:]]{3,4}|[[:xdigit:]]{6}|[[:xdigit:]]{8})$/

  defp settable?(%{type: :date}, value) when is_binary(value), do: match?({:ok, _}, Date.from_iso8601(value))

  defp settable?(%{type: :datetime}, value) when is_binary(value),
    do: match?({:ok, _, _}, DateTime.from_iso8601(value)) or match?({:ok, _}, NaiveDateTime.from_iso8601(value))

  # A link var takes an address, or an entry (above).
  defp settable?(%{type: :link}, value) when is_binary(value), do: value != ""
  defp settable?(_, _), do: false

  defp unsupported(%{type: :select}, key, value) when is_binary(value),
    do:
      problem(
        :unsupported_value,
        dgettext("content_proposals", "%{key} has no option %{value}.", key: key, value: value)
      )

  defp unsupported(_var, key, _value),
    do: problem(:unsupported_value, dgettext("content_proposals", "%{key} cannot be set to this value.", key: key))

  # Markdown is checked as the HTML it renders (`Brando.Markdown` leaves out
  # its raw HTML and unsafe addresses).
  # An `entry:` link in it never resolves, so it does not count as an
  # unresolved one, which would skip the check of the rest.
  defp checked_text("markdown", text),
    do: text |> Brando.Markdown.to_html!(breaks: true) |> String.replace(~r/href=(["'])\s*entry:/i, "href=\\1#")

  defp checked_text(_type, text), do: text

  # Text and markdown refs must pass the same safety check as the editor's
  # rich text; header refs hold plain text, and map refs an https embed
  # address. HTML and SVG refs hold markup only a superuser changes: an HTML
  # ref's parameters take values through `set_ref_config`.
  defp text(name, text, module) do
    case Enum.find(module.refs || [], &(&1.name == name)) do
      %{data: %{type: type}} when type in ["html", "svg"] ->
        [
          problem(
            :unsupported_value,
            dgettext("content_proposals", "%{name} holds markup only a superuser changes.", name: name)
          )
        ]

      %{data: %{type: type}} when is_binary(text) ->
        case text_problem(type, checked_text(type, text), name) do
          :unknown -> [unknown_text(name)]
          nil -> []
          message -> [problem(:unsafe_text, message)]
        end

      _ ->
        [unknown_text(name)]
    end
  end

  defp unknown_text(name),
    do: problem(:unknown_ref, dgettext("content_proposals", "The module has no text slot %{name}.", name: name))

  defp text_problem(type, text, name) when type in ["text", "markdown"], do: rich_text_problem(text, name)
  defp text_problem("header", text, name), do: plain_text_problem(text, name)

  defp text_problem("map", text, name) do
    unless embed_address?(text) and liquid_problem(text, name) == nil,
      do: dgettext("content_proposals", "%{name} takes an https Google Maps embed address.", name: name)
  end

  defp text_problem(_type, _text, _name), do: :unknown

  # A link to an entry that was not resolved is reported as such
  # (`link_problems/1`); the rest of the text is still checked.
  defp rich_text_problem(text, name) do
    liquid_problem(text, name) ||
      unless(text |> EntryLinks.blank_unresolved() |> Brando.RichText.safe_html?(),
        do: dgettext("content_proposals", "%{name} contains unsafe rich text.", name: name)
      )
  end

  defp plain_text_problem(text, name) do
    liquid_problem(text, name) ||
      if(String.contains?(text, ["<", ">"]), do: dgettext("content_proposals", "%{name} takes plain text.", name: name))
  end

  defp token_problem(text, name) do
    liquid_problem(text, name) ||
      if(String.contains?(text, ["<", ">", "\"", "'", "`", "="]),
        do: dgettext("content_proposals", "%{name} takes no quotes or markup.", name: name)
      )
  end

  # A module's output is rendered as Liquid once more when it holds a tag, and
  # a tag could write markup no check here saw. A proposed value holds no
  # opening brace at all, written out or as a character reference: one could
  # open a tag once the value is rendered (an attribute's references decoded,
  # Markdown's escapes, identifier attributes removed) or put next to another.
  @brace ~r/\{|&(#0*123(?![0-9])|#x0*7b(?![0-9a-f])|lbrace|lcub)/i
  defp liquid_problem(text, name) do
    if Regex.match?(@brace, text) or String.contains?(HtmlEntities.decode(text), "{"),
      do: dgettext("content_proposals", "%{name} cannot hold a {, which the page could read as Liquid.", name: name)
  end

  # A web, mail or phone address, or a path. Quotes, angle brackets and
  # character references are refused too: a template may put the address in
  # an attribute as it is.
  defp address_problem(text, name) do
    scheme = Regex.run(~r/^([a-z][a-z0-9+.-]*):/i, String.trim(text), capture: :all_but_first)

    address? =
      not Regex.match?(~r/[\x00-\x1f\x7f]/, text) and not unsafe_in_attribute?(text) and
        (scheme == nil or String.downcase(hd(scheme)) in ~w(http https mailto tel))

    liquid_problem(text, name) ||
      unless(address?, do: dgettext("content_proposals", "%{name} takes a web, mail or phone address.", name: name))
  end

  # A map is embedded from Google Maps (google.com, or a country's domain), over https.
  defp embed_address?(text) do
    case URI.new(text) do
      {:ok, %URI{scheme: "https", host: host}} when is_binary(host) ->
        Regex.match?(~r/(^|\.)google\.[a-z]{2,3}(\.[a-z]{2})?$/, host) and Brando.RichText.allowed_uri?(text) and
          not unsafe_in_attribute?(text)

      _ ->
        false
    end
  end

  defp unsafe_in_attribute?(text), do: Regex.match?(~r/["<>`]|&(#|[a-z][a-z0-9]*;)/i, text)

  defp unsafe(nil), do: []
  defp unsafe(message), do: [problem(:unsafe_text, message)]

  defp media(name, {kind, _} = asset, module, actor) when kind in [:image, :video, :file, :gallery] do
    case Enum.find(module.refs || [], &(&1.name == name)) do
      nil ->
        [problem(:unknown_ref, dgettext("content_proposals", "The module has no media slot %{name}.", name: name))]

      ref ->
        if kind in accepts(ref),
          do: assets(asset, gallery_types(ref), name, actor),
          else: [wrong_media(name)]
    end
  end

  defp media(_name, _asset, _module, _actor),
    do: [
      problem(:wrong_media_type, dgettext("content_proposals", "Only images, videos, files and galleries can be placed."))
    ]

  defp wrong_media(name),
    do: problem(:wrong_media_type, dgettext("content_proposals", "%{name} does not accept this media type.", name: name))

  # Every item of a gallery must be of a kind the gallery allows, and still in
  # the library.
  defp assets({:gallery, items}, types, name, actor) do
    if Enum.all?(items, fn {kind, _} -> kind in types end),
      do: Enum.flat_map(items, &assets(&1, types, name, actor)) |> Enum.uniq(),
      else: [wrong_media(name)]
  end

  defp assets({kind, id}, _types, _name, actor) do
    if match?({:error, _}, Error.protect(fn -> Dependencies.load!(to_string(kind), id, actor) end)),
      do: [problem(:missing_asset, dgettext("content_proposals", "This media is no longer in the library."))],
      else: []
  end

  defp gallery_types(%{data: %{type: "gallery", data: data}}), do: Map.get(data, :allowed_types) || [:image, :video]

  defp gallery_types(%{data: %{type: "media", data: %{template_gallery: %{allowed_types: [_ | _] = types}}}}),
    do: types

  defp gallery_types(%{gallery_allowed_types: [_ | _] = types}), do: types
  defp gallery_types(_), do: [:image, :video]

  @doc """
  The media kinds a module ref accepts: a picture ref takes an image, a video
  ref a video, a file ref a file, a gallery ref a gallery, and a media slot
  whichever of picture, video, gallery and file it makes available.
  """
  @spec accepts(Brando.Content.Ref.t()) :: [:image | :video | :file | :gallery]
  def accepts(%{data: %{type: "picture"}}), do: [:image]
  def accepts(%{data: %{type: "video"}}), do: [:video]
  def accepts(%{data: %{type: "file"}}), do: [:file]
  def accepts(%{data: %{type: "gallery"}}), do: [:gallery]

  def accepts(%{data: %{type: "media", data: data}}) do
    available = Map.get(data, :available_blocks) || ["picture", "video"]
    for {kind, type} <- @media_kinds, type in available, do: kind
  end

  def accepts(_), do: []

  defp check_changesets(proposal, entries, user) do
    proposal
    |> materialize!(entries, user)
    |> Enum.flat_map(fn {target, cs} -> Enum.map(changeset_problems(target, cs, user), &Map.put(&1, :target, target)) end)
  end

  defp changeset_problems(target, cs, user) do
    action = if match?({:new, _}, target), do: :create, else: :update

    cond do
      !cs.valid? ->
        errors = Changeset.traverse_errors(cs, fn {message, _} -> message end)
        [problem(:invalid, dgettext("content_proposals", "Entry validation: %{errors}", errors: inspect(errors)))]

      Boundary.change(user, action, cs) != :ok ->
        [problem(:forbidden, dgettext("content_proposals", "You do not have permission to save this entry."))]

      true ->
        taken(cs)
    end
  end

  defp taken(cs) do
    case Error.protect(fn -> Transfer.Entries.unique!(cs) end) do
      {:ok, _} -> []
      {:error, message} -> [problem(:taken, message)]
    end
  end

  defp problem(code, message), do: %{code: code, message: message}

  defp effects(proposal) do
    sources = sources(proposal.operations)

    existing =
      for {{schema, _} = target, entry} <- proposal.targets,
          schema != :new,
          target not in sources,
          do: {target, entry}

    inserted = for %{__struct__: kind, uid: uid} <- proposal.operations, kind in [InsertBlock, CopyBlock], do: uid
    deleted = for %DeleteBlock{} = op <- proposal.operations, do: {op.target, op.block_uid}

    changed = fn kinds ->
      proposal.operations
      |> Enum.filter(&(&1.__struct__ in kinds and &1.block_uid not in inserted))
      |> Enum.map(&{&1.target, &1.block_uid})
      |> Enum.uniq()
      |> Enum.reject(&(&1 in deleted))
      |> length()
    end

    %{
      creates: Enum.count(proposal.operations, &(&1.__struct__ in [CreateEntry, CreateTranslation])),
      updates: length(existing),
      inserted_blocks: length(inserted),
      updated_blocks:
        changed.([
          SetBlockMedia,
          SetBlockText,
          SetBlockValues,
          SetBlockActive,
          SetBlockDetails,
          SetRefConfig,
          SetBlockTable,
          SetBlockSelection
        ]),
      moved_blocks: changed.([MoveBlock]),
      deletions: deleted |> Enum.uniq() |> Enum.reject(&(elem(&1, 1) in inserted)) |> length(),
      replaced_images: Enum.count(proposal.operations, &match?(%ReplaceImageFile{}, &1)),
      live: for({target, %{status: :published}} <- existing, do: target)
    }
  end

  ## Notes

  @doc """
  Operations that change nothing: a block or ref switched to the state it is
  in, a value, text or media set to what is saved, details that are already
  so. Only the first change to each part of a block is compared with the
  saved block; later ones build on the proposal.

  Notes do not block a proposal. They tell the agent what to drop, and the
  reviewer why nothing seems to change.
  """
  @spec notes(Proposal.t()) :: [%{operation: non_neg_integer(), message: String.t()}]
  def notes(%Proposal{} = proposal) do
    proposal.operations
    |> Enum.with_index()
    |> Enum.reduce({[], MapSet.new()}, fn {op, index}, {notes, seen} ->
      key = Map.has_key?(op, :block_uid) && {Map.get(op, :target), op.block_uid, aspect(op)}

      notes =
        with true <- key && key not in seen,
             %{} = block <- saved_block(proposal, op),
             message when is_binary(message) <- unchanged(op, block) do
          [%{operation: index, message: message} | notes]
        else
          _ -> notes
        end

      {notes, if(key, do: MapSet.put(seen, key), else: seen)}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  # What an operation changes on a block. Only the first change to each is
  # compared with the saved block.
  defp aspect(%SetBlockActive{ref: ref}), do: {:active, ref}
  defp aspect(%SetBlockValues{values: values}), do: {:values, values |> Map.keys() |> Enum.sort()}
  defp aspect(%{ref: ref} = op), do: {op.__struct__, to_string(ref)}
  defp aspect(op), do: op.__struct__

  defp saved_block(proposal, %{target: target, field: field, block_uid: uid}) do
    with %{} = entry <- Map.get(proposal.targets, target),
         {block, _parent, _index} <- BlockTree.find_saved(entry_blocks(entry, field), uid) do
      block
    else
      _ -> nil
    end
  end

  defp unchanged(%SetBlockActive{ref: nil, active: active}, %{active: active}),
    do: "The block is already #{if active, do: "on", else: "off"}."

  defp unchanged(%SetBlockActive{ref: name, active: active}, block) do
    if Enum.any?(block.refs, &(&1.name == name and &1.active == active)),
      do: "Ref #{name} is already #{if active, do: "on", else: "off"}."
  end

  defp unchanged(%SetBlockValues{values: values}, block) do
    same =
      for {key, value} <- values,
          %{} = var <- [Enum.find(block.vars, &(&1.key == key))],
          saved_value(var) == value,
          do: key

    if same != [] and length(same) == map_size(values),
      do: "#{Enum.join(same, ", ")} already has this value.",
      else: if(same != [], do: "#{Enum.join(same, ", ")} already has this value; the rest change.")
  end

  defp unchanged(%SetBlockText{ref: name, text: text}, block) do
    if Enum.any?(block.refs, &(&1.name == to_string(name) and ref_text(&1) == text)),
      do: "Ref #{name} already has this text."
  end

  defp unchanged(%SetBlockMedia{ref: name, asset: {kind, id}}, block) when kind in [:image, :video, :file] do
    if Enum.any?(block.refs, &(&1.name == to_string(name) and Map.get(&1, :"#{kind}_id") == id)),
      do: "Ref #{name} already shows this #{kind}."
  end

  defp unchanged(%SetBlockDetails{} = op, block) do
    if Enum.all?([anchor: op.anchor, description: op.description], fn {key, value} ->
         is_nil(value) or (Map.get(block, key) || "") == value
       end),
       do: "The block already has these details."
  end

  defp unchanged(%SetRefConfig{ref: name, config: config}, block) do
    with %{} = ref <- Enum.find(block.refs, &(&1.name == name)),
         true <-
           Enum.all?(RefConfig.diff(ref, config), fn {_, before, value} -> to_string(before) == to_string(value) end) do
      "Ref #{name} already has these settings."
    else
      _ -> nil
    end
  end

  defp unchanged(_op, _block), do: nil

  defp saved_value(%{type: :boolean} = var), do: var.value_boolean
  defp saved_value(%{type: kind} = var) when kind in [:image, :video, :file], do: {kind, Map.get(var, :"#{kind}_id")}
  defp saved_value(var), do: var.value

  defp ref_text(%{data: %{data: data}}), do: Map.get(data, :text) || Map.get(data, :code) || Map.get(data, :embed_url)

  ## Materialize

  @doc """
  Build every target's changeset in memory from the frozen operations.

  Reloads the entries and refuses when one changed since `prepare/2`.
  Returns `%{target => changeset}`; nothing is saved.
  """
  @spec materialize(Proposal.t(), term()) :: {:ok, %{Proposal.target() => Changeset.t()}} | {:error, String.t()}
  def materialize(%Proposal{} = proposal, actor, opts \\ []) do
    Error.protect(fn ->
      # A proposal shared for review is read by a colleague, who needs only
      # to be able to read its entries.
      if opts[:shared], do: Transfer.ensure_scope!(actor), else: authorize_proposal!(proposal, actor)
      action = if opts[:shared], do: :read, else: :update
      materialize!(proposal, current!(proposal, actor, action), user!(actor))
    end)
  end

  # A translation has no changeset: it is the source's copy, made as the
  # proposal is applied (`create_translation!/2`).
  # A translation a `Translate` fills in is its pending version with the
  # texts written in (`Translations.work_changeset/4`).
  defp materialize!(proposal, entries, user) do
    for {target, _} <- proposal.targets, is_nil(translation(proposal.operations, target)), into: %{} do
      if translated?(proposal.operations, target),
        do: {target, translated_changeset!(target, proposal, user)},
        else: {target, target |> base_changeset(proposal, entries, user) |> put_blocks(target, proposal, entries, user)}
    end
  end

  defp translated_changeset!({schema, id} = target, proposal, user) do
    case Translations.work_changeset(schema, id, translated_answer(proposal, target).texts, user) do
      {:ok, changeset, _version_id} -> changeset
      {:error, reason} -> Error.fail!(translate_failed(reason))
    end
  end

  # Every batch's answer to `target`, as one save
  defp translated_answer(proposal, target) do
    for %Translate{target: ^target} = op <- proposal.operations, reduce: %{texts: %{}, acknowledged: []} do
      acc ->
        texts = for {key, text} <- (is_map(op.texts) && op.texts) || %{}, is_binary(text), into: %{}, do: {key, text}
        reviewed = if is_list(op.reviewed), do: Enum.filter(op.reviewed, &is_binary/1), else: []
        %{texts: Map.merge(acc.texts, texts), acknowledged: acc.acknowledged ++ reviewed}
    end
  end

  defp translate_failed({:source_controlled, paths}),
    do:
      dgettext(
        "content_proposals",
        "The translation's structure or media would no longer follow its source: %{paths}. Read translation_work again.",
        paths: Enum.join(paths, ", ")
      )

  defp translate_failed(%Changeset{} = changeset),
    do:
      dgettext("content_proposals", "Entry validation: %{errors}",
        errors: inspect(Changeset.traverse_errors(changeset, fn {message, _} -> message end))
      )

  defp translate_failed(:unbuildable),
    do:
      dgettext(
        "content_proposals",
        "The translation's pending version could not be opened. Open the translation in the admin, then read translation_work again."
      )

  defp translate_failed(_reason),
    do:
      dgettext(
        "content_proposals",
        "This entry is not a synchronized translation, so it has no translation work to answer."
      )

  @doc """
  A `create_entry`'s fields as the new entry gets them. A content type with
  a `language` field gets the site's default language when the fields leave
  it out. Preview, review and apply all build the entry from these.
  """
  @spec new_entry_fields(module(), map()) :: map()
  def new_entry_fields(schema, fields) do
    language = new_entry_language(schema)

    if language && fields["language"] in [nil, ""],
      do: Map.put(fields, "language", language),
      else: fields
  end

  @doc """
  The language a new entry of `schema` gets when its fields leave it out:
  the site's default, when the content type's `language` is a language
  field that takes it and has no default of its own. Otherwise `nil`.
  """
  @spec new_entry_language(module()) :: String.t() | nil
  def new_entry_language(schema) do
    with true <- :language in schema.__schema__(:fields),
         nil <- Map.get(struct(schema), :language),
         default when not is_nil(default) <- Brando.Languages.default_language(),
         default = to_string(default),
         true <- default in language_values(schema) do
      default
    else
      _ -> nil
    end
  end

  @doc """
  The languages a new entry of `schema` can take, as
  `[%{code: "en", name: "English"}, …]`: the current site's languages that
  its `language` field accepts, in the site's order. Empty when the content
  type has no `language` field of the language kind.
  """
  @spec entry_languages(module()) :: [%{code: String.t(), name: String.t()}]
  def entry_languages(schema) do
    values = language_values(schema)

    listed =
      for language <- Brando.Languages.languages(),
          code = to_string(language[:value]),
          code in values,
          do: %{code: code, name: language[:text]}

    # A field whose own languages are none of the site's still takes them.
    if listed == [], do: Enum.map(values, &%{code: &1, name: &1}), else: listed
  end

  # A `language` field of another kind (plain text, say) is not ours to fill.
  defp language_values(schema) do
    case schema.__schema__(:type, :language) do
      {:parameterized, {Ecto.Enum, _}} -> schema |> Ecto.Enum.values(:language) |> Enum.map(&to_string/1)
      _ -> []
    end
  end

  # A locked `language` is dropped from a non-superuser's params; without a
  # default from the form it would be saved empty.
  defp put_new_entry_language(changeset, schema) do
    case new_entry_language(schema) do
      language when is_binary(language) ->
        if Changeset.get_field(changeset, :language) == nil,
          do: Changeset.cast(changeset, %{"language" => language}, [:language]),
          else: changeset

      nil ->
        changeset
    end
  end

  defp base_changeset({:new, ref} = target, proposal, _entries, user) do
    schema = Map.fetch!(proposal.targets, target)
    %CreateEntry{fields: fields} = Enum.find(proposal.operations, &match?(%CreateEntry{ref: ^ref}, &1))
    entry = struct(schema)
    params = EntryFields.params(schema, new_entry_fields(schema, fields))
    cast = &schema.changeset(entry, Map.put(&1, "status", "draft"), user, nil, [])

    # What a non-superuser can't name (`locked_fields/3`) it has as a form's new
    # entry has it. The role is the author's here too: a colleague may be
    # reading the review.
    changeset =
      if Boundary.superuser?(%Brando.Users.User{id: proposal.actor_id}),
        do: cast.(params),
        else: LockedFields.cast_held(params, schema, entry, cast)

    put_new_entry_language(changeset, schema)
  end

  defp base_changeset({schema, _} = target, proposal, entries, user) do
    fields =
      for %SetFields{target: ^target, fields: fields} <- proposal.operations,
          reduce: %{},
          do: (acc -> Map.merge(acc, fields))

    entry = entries |> Map.fetch!(target) |> EntryFields.preload(Map.keys(fields))
    schema.changeset(entry, EntryFields.params(schema, fields), user, nil, [])
  end

  defp put_blocks(changeset, target, proposal, entries, user) do
    schema = changeset.data.__struct__

    # A copy from another entry or field arrives here with its saved original.
    ops =
      proposal.operations
      |> Enum.flat_map(fn
        %CopyBlock{to_target: to} = op when not is_nil(to) ->
          if to == target, do: [{op.to_field, {:copy_in, op, copy_source(op, entries)}}], else: []

        op ->
          if Map.get(op, :target) == target and Map.has_key?(op, :field), do: [{op.field, op}], else: []
      end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    # A new entry gets every block field, empty or not: renderers and
    # templates read them, and an unsaved struct has them unloaded.
    ops =
      if match?({:new, _}, target),
        do: Map.merge(Map.new(schema.__blocks_fields__(), &{to_string(&1.name), []}), ops),
        else: ops

    changeset =
      Enum.reduce(ops, changeset, fn {field, ops}, cs ->
        assoc = :"entry_#{field}"
        join_schema = Module.concat(schema, Macro.camelize(field))

        saved =
          case Map.get(entries, target) do
            nil -> []
            entry -> Enum.map(Map.fetch!(entry, assoc), &{&1.block.uid, Changeset.change(&1)})
          end

        joins =
          ops
          |> Enum.reduce(saved, &block_op(&1, &2, join_schema, user))
          |> Enum.with_index(fn {_uid, join}, sequence -> Changeset.change(join, sequence: sequence) end)

        Changeset.put_assoc(cs, assoc, joins)
      end)

    if schema.__blocks_fields__() == [], do: changeset, else: Blocks.render_block_fields(changeset)
  end

  defp copy_source(op, entries) do
    {block, _parent, _index} =
      entries |> Map.fetch!(op.target) |> Map.fetch!(:"entry_#{op.field}") |> BlockTree.find_saved(op.block_uid)

    Changeset.change(block)
  end

  # `joins` is the field's root join rows as `[{uid, join_changeset}]`; child
  # blocks are reached through each block's `children` association.
  defp block_op(%InsertBlock{parent: nil} = op, joins, join_schema, user) do
    join =
      join_schema
      |> struct()
      |> Changeset.change()
      |> Changeset.put_assoc(:block, new_block(op, join_schema, user, :module))
      |> Map.put(:action, :insert)

    BlockTree.insert_at(joins, {op.uid, join}, op.placement, &elem(&1, 0))
  end

  defp block_op(%InsertBlock{} = op, joins, join_schema, user) do
    update_block(joins, op.parent, fn parent ->
      type = if Changeset.get_field(parent, :multi), do: :module_entry, else: :module
      block = new_block(op, join_schema, user, type)

      put_children(
        parent,
        &BlockTree.insert_at(&1, block, op.placement, fn child -> Changeset.get_field(child, :uid) end)
      )
    end)
  end

  defp block_op(%MoveBlock{block_uid: uid, placement: placement}, joins, join_schema, _user) do
    from = parent_of(joins, uid)

    to =
      case placement do
        :append -> from
        {:into, parent} -> {:ok, parent}
        {_side, anchor} -> parent_of(joins, anchor)
      end

    if to == from,
      do: reorder(joins, uid, placement),
      else: joins |> detach(uid, from) |> attach(to, placement, join_schema)
  end

  defp block_op(%CopyBlock{block_uid: uid, placement: placement} = op, joins, join_schema, user) do
    to =
      case placement do
        :append -> parent_of(joins, uid)
        {:into, parent} -> {:ok, parent}
        {_side, anchor} -> parent_of(joins, anchor)
      end

    original = find_block(joins, uid)
    copy = Blocks.duplicate_block(original, user_id: user.id, uid: op.uid, uid_mapping: copy_uids(original, op.uid))
    # "append" puts the copy last among the original's siblings.
    attach({copy, joins}, to, placement, join_schema)
  end

  defp block_op(%SetRefConfig{} = op, joins, _join_schema, _user) do
    update_block(
      joins,
      op.block_uid,
      &update_refs(&1, fn ref ->
        if Changeset.get_field(ref, :name) == op.ref, do: RefConfig.put(ref, op.config), else: ref
      end)
    )
  end

  defp block_op({:copy_in, op, original}, joins, join_schema, user) do
    to =
      case op.placement do
        :append -> :root
        {:into, parent} -> {:ok, parent}
        {_side, anchor} -> parent_of(joins, anchor)
      end

    copy =
      Blocks.duplicate_block(original,
        user_id: user.id,
        uid: op.uid,
        uid_mapping: copy_uids(original, op.uid),
        source: join_schema
      )

    attach({copy, joins}, to, op.placement, join_schema)
  end

  defp block_op(%SetBlockTable{} = op, joins, _join_schema, _user) do
    update_block(joins, op.block_uid, fn block ->
      module =
        Content.fetch_module(Changeset.get_field(block, :module_id), Changeset.get_field(block, :module_origin) || :local)

      vars = table_vars(module)

      rows =
        op.rows
        |> Enum.with_index()
        |> Enum.map(fn {row, sequence} ->
          %{sequence: sequence, vars: Enum.map(vars, &table_var(&1, row))}
        end)

      Changeset.put_assoc(block, :table_rows, rows)
    end)
  end

  defp block_op(%SetBlockSelection{} = op, joins, _join_schema, _user) do
    update_block(joins, op.block_uid, fn block ->
      selection =
        op.identifiers |> Enum.with_index() |> Enum.map(fn {id, sequence} -> %{identifier_id: id, sequence: sequence} end)

      Changeset.put_assoc(block, :block_identifiers, selection)
    end)
  end

  defp block_op(%SetBlockDetails{} = op, joins, _join_schema, _user) do
    changes = for {key, value} <- [anchor: op.anchor, description: op.description], not is_nil(value), do: {key, value}
    update_block(joins, op.block_uid, &Changeset.change(&1, changes))
  end

  defp block_op(%SetBlockActive{ref: nil} = op, joins, _join_schema, _user),
    do: update_block(joins, op.block_uid, &Changeset.put_change(&1, :active, op.active))

  defp block_op(%SetBlockActive{} = op, joins, _join_schema, _user) do
    update_block(
      joins,
      op.block_uid,
      &update_refs(&1, fn ref ->
        if Changeset.get_field(ref, :name) == op.ref, do: Changeset.put_change(ref, :active, op.active), else: ref
      end)
    )
  end

  defp block_op(%DeleteBlock{block_uid: uid}, joins, _join_schema, _user) do
    if List.keymember?(joins, uid, 0),
      do: List.keydelete(joins, uid, 0),
      else: update_siblings(joins, uid, fn children -> Enum.reject(children, &(Changeset.get_field(&1, :uid) == uid)) end)
  end

  defp block_op(%SetBlockMedia{} = op, joins, _join_schema, user) do
    name = to_string(op.ref)

    update_block(joins, op.block_uid, fn block ->
      module =
        Content.fetch_module(Changeset.get_field(block, :module_id), Changeset.get_field(block, :module_origin) || :local)

      update_refs(block, &if(Changeset.get_field(&1, :name) == name, do: put_media(&1, op.asset, module, user), else: &1))
    end)
  end

  defp block_op(%SetBlockText{} = op, joins, _join_schema, _user) do
    name = to_string(op.ref)

    update_block(
      joins,
      op.block_uid,
      &update_refs(&1, fn ref -> if Changeset.get_field(ref, :name) == name, do: put_text(ref, op.text), else: ref end)
    )
  end

  defp block_op(%SetBlockValues{} = op, joins, _join_schema, user),
    do: update_block(joins, op.block_uid, &put_values(&1, op.values, user))

  defp new_block(%InsertBlock{} = op, join_schema, user, type) do
    module = fetch_module(op.module)

    op.module
    |> Content.SharedLibrary.reference()
    |> Blocks.build_module_block(user.id, nil, join_schema, type)
    |> Changeset.put_change(:uid, op.uid)
    |> update_refs(fn ref ->
      name = Changeset.get_field(ref, :name)
      ref = Changeset.put_change(ref, :uid, Map.fetch!(op.ref_uids, name))
      ref = if text = op.texts[name], do: put_text(ref, text), else: ref
      ref = if asset = op.media[name], do: put_media(ref, asset, module, user), else: ref
      RefConfig.put(ref, op.configs[name] || %{})
    end)
    |> put_values(op.values, user)
  end

  defp reorder(joins, uid, placement) do
    case List.keytake(joins, uid, 0) do
      {root, rest} ->
        BlockTree.insert_at(rest, root, placement, &elem(&1, 0))

      nil ->
        update_siblings(joins, uid, fn children ->
          {child, rest} = Enum.split_with(children, &(Changeset.get_field(&1, :uid) == uid))
          BlockTree.insert_at(rest, hd(child), placement, &Changeset.get_field(&1, :uid))
        end)
    end
  end

  # `:root` or `{:ok, parent_uid}` of the block `uid`.
  defp parent_of(joins, uid) do
    if List.keymember?(joins, uid, 0),
      do: :root,
      else: Enum.find_value(joins, fn {_, join} -> parent_in(Changeset.get_assoc(join, :block), uid) end)
  end

  defp parent_in(block, uid) do
    children = children(block)

    if Enum.any?(children, &(Changeset.get_field(&1, :uid) == uid)),
      do: {:ok, Changeset.get_field(block, :uid)},
      else: Enum.find_value(children, &parent_in(&1, uid))
  end

  # A block moving to another parent keeps its row: it leaves the old list
  # and is saved as an update under the new parent, which sets `parent_id`.
  # The old parent must not count it as removed — `on_replace` would delete
  # the row — so it is taken out of the old parent's loaded children too. A
  # root block's join row goes; the block is updated through its new parent.
  defp detach(joins, uid, :root) do
    {{^uid, join}, rest} = List.keytake(joins, uid, 0)
    {Changeset.get_assoc(join, :block), rest}
  end

  defp detach(joins, uid, {:ok, parent}) do
    block = find_block(joins, uid)

    joins =
      update_block(joins, parent, fn parent ->
        parent =
          case parent.data.children do
            loaded when is_list(loaded) ->
              %{parent | data: %{parent.data | children: Enum.reject(loaded, &(&1.uid == uid))}}

            _ ->
              parent
          end

        put_children(parent, fn children -> Enum.reject(children, &(Changeset.get_field(&1, :uid) == uid)) end)
      end)

    {block, joins}
  end

  defp attach({block, joins}, :root, placement, join_schema) do
    join =
      join_schema
      |> struct()
      |> Changeset.change()
      |> Changeset.put_assoc(:block, Changeset.put_change(block, :parent_id, nil))
      |> Map.put(:action, :insert)

    BlockTree.insert_at(joins, {Changeset.get_field(block, :uid), join}, placement, &elem(&1, 0))
  end

  defp attach({block, joins}, {:ok, parent}, placement, _join_schema) do
    update_block(joins, parent, fn parent ->
      put_children(parent, &BlockTree.insert_at(&1, block, placement, fn child -> Changeset.get_field(child, :uid) end))
    end)
  end

  # The uids a copy gives to the blocks below the original (`duplicate_block/2`
  # maps every uid in the tree, slots included).
  defp copy_uids(block, copy) do
    block
    |> tree_uids()
    |> Map.new(&{&1, BlockTree.copy_uid(copy, &1)})
    |> Map.put(Changeset.get_field(block, :uid), copy)
  end

  defp tree_uids(block), do: [Changeset.get_field(block, :uid) | Enum.flat_map(children(block), &tree_uids/1)]

  defp find_block(joins, uid) do
    Enum.find_value(joins, fn {_, join} -> find_in_block(Changeset.get_assoc(join, :block), uid) end)
  end

  defp find_in_block(block, uid) do
    if Changeset.get_field(block, :uid) == uid,
      do: block,
      else: block |> children() |> Enum.find_value(&find_in_block(&1, uid))
  end

  # Apply `fun` to the block `uid`, wherever it is in the field.
  defp update_block(joins, uid, fun) do
    Enum.map(joins, fn {root_uid, join} = root ->
      case update_in_block(Changeset.get_assoc(join, :block), uid, fun) do
        {:ok, block} -> {root_uid, Changeset.put_assoc(join, :block, block)}
        :error -> root
      end
    end)
  end

  defp update_in_block(block, uid, fun) do
    if Changeset.get_field(block, :uid) == uid,
      do: {:ok, fun.(block)},
      else: update_in_children(block, &update_in_block(&1, uid, fun))
  end

  # Apply `fun` to the list of children that holds the child block `uid`.
  defp update_siblings(joins, uid, fun) do
    Enum.map(joins, fn {root_uid, join} = root ->
      case siblings_in_block(Changeset.get_assoc(join, :block), uid, fun) do
        {:ok, block} -> {root_uid, Changeset.put_assoc(join, :block, block)}
        :error -> root
      end
    end)
  end

  defp siblings_in_block(block, uid, fun) do
    if Enum.any?(children(block), &(Changeset.get_field(&1, :uid) == uid)),
      do: {:ok, put_children(block, fun)},
      else: update_in_children(block, &siblings_in_block(&1, uid, fun))
  end

  # The first child `fun` finds its block in, replaced; `:error` if none.
  defp update_in_children(block, fun) do
    children = children(block)

    children
    |> Enum.with_index()
    |> Enum.find_value(:error, fn {child, index} ->
      case fun.(child) do
        {:ok, child} -> {:ok, Changeset.put_assoc(block, :children, List.replace_at(children, index, child))}
        :error -> nil
      end
    end)
  end

  # The live children of a block changeset. Removed children come back from
  # `get_assoc` as `:replace` changesets, which `put_assoc` must not be given.
  defp children(block),
    do: block |> Changeset.get_assoc(:children) |> Enum.reject(&(&1.action in [:replace, :delete]))

  # Rewrite a block's children and number them in their new order.
  defp put_children(block, fun) do
    children =
      block
      |> children()
      |> fun.()
      |> Enum.with_index(fn child, sequence -> Changeset.put_change(child, :sequence, sequence) end)

    Changeset.put_assoc(block, :children, children)
  end

  defp update_refs(block, fun), do: Changeset.put_assoc(block, :refs, Enum.map(Changeset.get_assoc(block, :refs), fun))

  # A media slot is retyped from its module definition's template, as the
  # editor's media block does when an editor picks a picture, a video, a
  # gallery or a file.
  defp put_media(ref, {kind, value}, module, user) do
    type = Map.fetch!(@media_kinds, kind)
    name = Changeset.get_field(ref, :name)

    ref =
      if Changeset.get_field(ref, :data).type == type do
        ref
      else
        definition = Enum.find(module.refs, &(&1.name == name))

        ref
        |> Changeset.put_change(:data, template(definition, type))
        |> Changeset.put_change(:image_id, nil)
        |> Changeset.put_change(:video_id, nil)
        |> Changeset.put_change(:gallery_id, nil)
        |> Changeset.put_change(:file_id, nil)
      end

    if kind == :gallery,
      do: put_gallery(ref, value, "ref:gallery", user),
      else: Changeset.put_change(ref, :"#{kind}_id", value)
  end

  # A gallery's objects are replaced in order; a ref or var without a gallery
  # gets a new one, as the editor does when the first item is picked.
  defp put_gallery(changeset, items, config_target, user) do
    objects =
      items
      |> Enum.with_index()
      |> Enum.map(fn {{kind, id}, sequence} -> %{:"#{kind}_id" => id, sequence: sequence, creator_id: user.id} end)

    case Changeset.get_field(changeset, :gallery) do
      %Brando.Galleries.Gallery{} = gallery ->
        gallery = gallery |> Changeset.change() |> Changeset.put_assoc(:gallery_objects, objects)
        Changeset.put_assoc(changeset, :gallery, gallery)

      _ ->
        Changeset.put_assoc(changeset, :gallery, %{config_target: config_target, gallery_objects: objects})
    end
  end

  # The field a ref's content lives in, by ref type.
  # Never an HTML or SVG ref's markup (`text/3` refuses it before this).
  defp put_text(ref, text) do
    case Changeset.get_field(ref, :data) do
      %{type: type} when type in ["html", "svg"] ->
        ref

      %{type: type, data: inner} = block ->
        key = if type == "map", do: :embed_url, else: :text
        Changeset.put_change(ref, :data, %{block | data: Map.put(inner, key, text)})
    end
  end

  defp template(%{data: %{type: "media", data: data}}, "picture"),
    do: %Brando.Villain.Blocks.PictureBlock{
      type: "picture",
      data: normalize_caption(data.template_picture || %Brando.Villain.Blocks.PictureBlock.Data{})
    }

  defp template(%{data: %{type: "media", data: data}}, "video"),
    do: %Brando.Villain.Blocks.VideoBlock{
      type: "video",
      data: normalize_caption(data.template_video || %Brando.Villain.Blocks.VideoBlock.Data{})
    }

  defp template(%{data: %{type: "media", data: data}}, "gallery"),
    do: %Brando.Villain.Blocks.GalleryBlock{
      type: "gallery",
      data: data.template_gallery || %Brando.Villain.Blocks.GalleryBlock.Data{}
    }

  defp template(%{data: %{type: "media", data: data}}, "file"),
    do: %Brando.Villain.Blocks.FileBlock{
      type: "file",
      data: data.template_file || %Brando.Villain.Blocks.FileBlock.Data{}
    }

  # A template's caption is rich text, which the module's template doesn't
  # store as a ref does (`Brando.Captions.normalize/1`)
  defp normalize_caption(data), do: %{data | title: Brando.Captions.normalize(data.title)}

  defp put_values(block, values, _user) when values == %{}, do: block

  defp put_values(block, values, user) do
    vars =
      block
      |> Changeset.get_assoc(:vars)
      |> Enum.map(fn var ->
        case Map.fetch(values, Changeset.get_field(var, :key)) do
          {:ok, value} -> put_value(var, Changeset.get_field(var, :type), value, user)
          :error -> var
        end
      end)

    Changeset.put_assoc(block, :vars, vars)
  end

  # A new table row's variable, from its template with the row's value. Maps,
  # not structs: `put_assoc` inserts each as its own row.
  @var_owners [:__meta__, :id, :inserted_at, :updated_at, :module_id, :block_id, :table_template_id, :table_row_id]

  defp table_var(template, row) do
    var = template |> Map.from_struct() |> Map.drop(@var_owners ++ Brando.Content.Var.__schema__(:associations))

    case Map.fetch(row, template.key) do
      {:ok, value} -> Map.merge(var, var_value(template.type, value))
      :error -> var
    end
  end

  defp var_value(:boolean, value), do: %{value_boolean: value}
  defp var_value(kind, {kind, id}) when kind in [:image, :video, :file], do: %{:"#{kind}_id" => id}

  defp var_value(:link, {:link, target, opts}),
    do: Map.merge(if(target, do: var_value(:link, target), else: %{}), link_options(opts))

  defp var_value(:link, {:entry, schema, id}) do
    {:ok, identifier} = Content.get_identifier(schema, %{id: id})
    %{link_type: :identifier, identifier_id: identifier.id}
  end

  defp var_value(:link, url), do: %{link_type: :url, value: url}
  defp var_value(_type, value), do: %{value: value}

  defp put_value(var, :boolean, value, _user), do: Changeset.put_change(var, :value_boolean, value)
  defp put_value(var, :gallery, {:gallery, items}, user), do: put_gallery(var, items, "default", user)

  defp put_value(var, kind, {kind, id}, _user) when kind in [:image, :video, :file],
    do: Changeset.put_change(var, :"#{kind}_id", id)

  defp put_value(var, :link, {:link, target, opts}, user) do
    var = if target, do: put_value(var, :link, target, user), else: var
    Changeset.change(var, link_options(opts))
  end

  defp put_value(var, :link, {:entry, schema, id}, _user) do
    {:ok, identifier} = Content.get_identifier(schema, %{id: id})
    Changeset.change(var, link_type: :identifier, identifier_id: identifier.id)
  end

  defp put_value(var, :link, url, _user) when is_binary(url), do: Changeset.change(var, link_type: :url, value: url)
  defp put_value(var, _type, value, _user), do: Changeset.put_change(var, :value, value)

  # An empty text leaves the link to show its default: an entry's title.
  defp link_options(opts) do
    Enum.reduce(opts, %{}, fn
      {:text, text}, acc -> Map.put(acc, :link_text, if(text == "", do: nil, else: text))
      {:new_tab, new_tab}, acc -> Map.put(acc, :link_target_blank, new_tab)
    end)
  end

  ## Store, approve and apply

  @ttl :timer.hours(24)

  @doc """
  Prepare `operations` and store them as a proposal version for review.

  Options:

    * `:conversation_id` — the conversation the proposal belongs to
    * `:supersedes` — the id of the proposal this one refines. It is marked
      `superseded`, its approval lapses, and this proposal takes the next version.
    * `:summary` — a short description for review
    * `:origin` — where the proposal comes from: `:assistant` (the default
      with a conversation) or `:mcp`, a tool connected over MCP
    * `:client` — the connected tool's name, such as "Claude Code", when it
      is known
    * `:replaces` — for a proposal without a conversation, from a connected
      tool: the id of the actor's proposal from the same client that this one
      refines, or `:latest`. With `:latest`, the most recent proposal from the
      same actor and client still under review is superseded when it has
      problems or touches an entry this one touches (the same target, or a
      created entry with the same content type, language and slug — or uri
      for pages, or title when it gives neither); otherwise it is left
      alone and this one starts at version 1. Calls for one actor and client
      are serialized while the earlier proposal is found and superseded, so
      concurrent calls never leave two versions under review.

  A refinement keeps the origin and client of the version it supersedes.
  Proposals without a conversation are listed for review by
  `list_external/2`.

  Validation problems do not fail; they are stored and block approval.
  """
  @spec propose([struct()], term(), keyword()) :: {:ok, Proposal.t()} | {:error, String.t()}
  def propose(operations, actor, opts \\ []) do
    with {:ok, proposal} <- prepare(operations, actor) do
      Error.protect(fn -> store!(proposal, actor, opts) end)
    end
  end

  defp store!(proposal, actor, opts) do
    {:ok, {record, previous}} =
      Repo.transaction(fn ->
        previous =
          case opts[:replaces] do
            nil -> supersede!(opts[:supersedes], actor)
            replaces -> replace!(replaces, proposal, actor, opts)
          end

        {Repo.insert!(new_record(proposal, previous, opts)), previous}
      end)

    %{with_record(proposal, record) | supersedes_summary: previous && previous.summary}
  end

  # A connected tool's proposals: the earlier one is found and superseded
  # under a lock for the actor and client, so a second call that arrives
  # while the first is stored waits for it and then refines it.
  defp replace!(replaces, proposal, actor, opts) do
    client = client(opts[:client])

    Ecto.Adapters.SQL.query!(Repo.repo(), "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
      "brando-content-proposal-client:#{Transfer.scope()}:#{user!(actor).id}:#{client}"
    ])

    previous =
      case replaces do
        :latest -> actor |> under_review_from_client(client) |> Enum.find(&replaced_by?(&1, proposal))
        id -> replaceable!(id, actor, client)
      end

    previous && previous |> Changeset.change(status: "superseded") |> Repo.update!()
  end

  # The newest proposal that has problems or shares an entry is replaced. An
  # older one about the same entry counts too, when a proposal about another
  # entry came in between.
  defp replaced_by?(previous, proposal), do: previous.problems != [] or overlaps?(previous, proposal)

  # Newest first. An expired proposal can no longer be approved, so it is not
  # under review.
  defp under_review_from_client(actor, client) do
    Repo.all(
      from(r in external(actor),
        where: r.status in ~w(pending approved) and r.expires_at > ^DateTime.utc_now(),
        order_by: [desc: r.inserted_at, desc: r.version],
        lock: "FOR UPDATE"
      )
      |> where_client(client)
    )
  end

  defp where_client(query, nil), do: from(r in query, where: is_nil(r.client))
  defp where_client(query, client), do: from(r in query, where: r.client == ^client)

  defp replaceable!(id, actor, client) do
    record =
      case Ecto.UUID.cast(id) do
        {:ok, id} -> Repo.one(from(r in external(actor), where: r.id == ^id, lock: "FOR UPDATE"))
        :error -> nil
      end

    cond do
      is_nil(record) or record.client != client ->
        Error.fail!(
          dgettext(
            "content_proposals",
            "replaces: there is no proposal %{id} from this tool. Leave out replaces to store a new proposal.",
            id: inspect(id)
          )
        )

      record.status not in ~w(pending approved) or DateTime.compare(record.expires_at, DateTime.utc_now()) == :lt ->
        Error.fail!(
          dgettext(
            "content_proposals",
            "replaces: proposal %{id} is no longer under review. Leave out replaces to store a new proposal.",
            id: inspect(id)
          )
        )

      true ->
        record
    end
  end

  # Whether a stored proposal touches an entry `proposal` touches.
  defp overlaps?(record, proposal) do
    case Codec.decode_all(record.operations) do
      {:ok, operations} -> not MapSet.disjoint?(touched(operations), touched(proposal.operations))
      {:error, _} -> false
    end
  end

  # A ref is a name inside one proposal, so a created entry is told apart by
  # its content type, language and address (`created/1`). One without an
  # address overlaps with nothing.
  # An image a replacement swaps counts as touched, both of them.
  defp touched(operations) do
    creates =
      for %type{ref: ref} = op <- operations, type in [CreateEntry, CreateTranslation], into: %{}, do: {ref, created(op)}

    entries =
      for op <- operations, target <- changed_targets(op), not is_nil(target), into: MapSet.new() do
        case target do
          {:new, ref} -> creates[ref] || {:new, make_ref()}
          target -> target
        end
      end

    for %ReplaceImageFile{asset: old, with: new} <- operations, image <- [old, new], into: entries, do: image
  end

  # The slug, or the uri (pages), or the key under its parent key
  # (fragments), or else the title, as the create gives it: trimmed and
  # case-insensitive, without slug generation. A blank value is no address.
  # A translation is the same when it is of the same source, in the same language.
  defp created(%CreateTranslation{source: {schema, id}, language: language}), do: {:translation, schema, id, language}

  defp created(%CreateEntry{schema: schema, fields: fields}) do
    fields = Map.new(fields, fn {key, value} -> {to_string(key), value} end)
    address = Enum.find_value(~w(slug uri key title), &address(&1, fields))

    address && {:new, schema, normalized(fields["language"]), address}
  end

  defp address("key", fields) do
    case present(fields["key"]) do
      nil -> nil
      key -> {:key, present(fields["parent_key"]), key}
    end
  end

  defp address(field, fields), do: present(fields[field])

  defp present(value) do
    case normalized(value) do
      "" -> nil
      value -> value
    end
  end

  defp normalized(value) when is_binary(value), do: value |> String.trim() |> String.downcase()
  defp normalized(value) when is_atom(value) and not is_nil(value), do: normalized(to_string(value))
  defp normalized(_value), do: nil

  defp supersede!(nil, _actor), do: nil

  defp supersede!(id, actor) do
    previous = record!(id, actor, lock: true)

    if previous.status not in ~w(pending approved),
      do: Error.fail!(dgettext("content_proposals", "Only a proposal under review can be refined."))

    previous |> Changeset.change(status: "superseded") |> Repo.update!()
  end

  defp new_record(proposal, previous, opts) do
    conversation_id = if(previous, do: previous.conversation_id, else: opts[:conversation_id])
    {origin, client} = origin(previous, conversation_id, opts)

    %Record{
      id: proposal.id,
      conversation_id: conversation_id,
      origin: origin,
      client: client,
      version: if(previous, do: previous.version + 1, else: 1),
      supersedes_id: previous && previous.id,
      scope: proposal.scope,
      actor_id: proposal.actor_id,
      summary: opts[:summary],
      operations: Enum.map(proposal.operations, &Codec.encode/1),
      fingerprints: Map.new(proposal.fingerprints, fn {target, digest} -> {Proposal.key(target), digest} end),
      module_versions:
        for(
          {{origin, id}, version} <- proposal.module_versions,
          do: %{"origin" => to_string(origin), "id" => id, "version" => version}
        ),
      problems: Enum.map(proposal.problems, &encode_problem/1),
      effects: encode_effects(proposal.effects),
      status: "pending",
      expires_at: DateTime.add(DateTime.utc_now(), @ttl, :millisecond)
    }
  end

  # A refinement keeps where the proposal came from unless told otherwise.
  defp origin(nil, conversation_id, opts),
    do: {origin!(opts[:origin]) || (conversation_id && "assistant"), client(opts[:client])}

  defp origin(previous, _conversation_id, opts),
    do: {origin!(opts[:origin]) || previous.origin, client(opts[:client]) || previous.client}

  defp origin!(nil), do: nil

  defp origin!(origin) do
    origin = to_string(origin)

    if origin in Record.origins(),
      do: origin,
      else: Error.fail!(dgettext("content_proposals", "Unknown proposal origin."))
  end

  # A connected tool names itself; keep a short, single line of it.
  @client_length 80

  defp client(client) when is_binary(client) do
    case client |> String.replace(~r/\s+/u, " ") |> String.trim() do
      "" -> nil
      client -> String.slice(client, 0, @client_length)
    end
  end

  defp client(_), do: nil

  @doc """
  Load a stored proposal version. Its entries are read as they are now; the
  fingerprints are the ones captured when it was prepared, so a preview or
  apply of changed content is refused.
  """
  @spec get(Ecto.UUID.t(), term()) :: {:ok, Proposal.t()} | {:error, String.t()}
  def get(id, actor), do: Error.protect(fn -> rebuild!(record!(id, actor), actor) end)

  @doc "The stored proposal versions of a conversation, newest first."
  @spec list(Ecto.UUID.t(), term()) :: [Record.t()]
  def list(conversation_id, actor) do
    Repo.all(
      from(r in Record,
        where: r.conversation_id == ^conversation_id and r.scope == ^Transfer.scope() and r.actor_id == ^user!(actor).id,
        order_by: [desc: r.version]
      )
    )
  end

  @doc """
  The actor's proposals in this site/environment that came from outside the
  admin's conversations — from a tool connected over MCP — newest first.

  Proposals under review and applied or undone ones are listed; superseded
  and discarded versions are not. The records carry what a list shows, not
  their operations: load one with `get/2` to review it. Options: `:limit`
  (default 30).
  """
  @spec list_external(term(), keyword()) :: [Record.t()]
  def list_external(actor, opts \\ []) do
    Repo.all(
      from(r in external(actor),
        where: r.status not in ~w(superseded cancelled),
        order_by: [desc: r.inserted_at],
        limit: ^Keyword.get(opts, :limit, 30),
        select:
          struct(r, [:id, :version, :scope, :actor_id, :summary, :origin, :client, :status, :expires_at, :inserted_at])
      )
    )
  end

  @doc """
  How many of the actor's proposals from outside the admin's conversations
  wait for review in this site/environment: pending or approved, and not
  expired.
  """
  @spec count_external(term()) :: non_neg_integer()
  def count_external(actor) do
    now = DateTime.utc_now()

    Repo.aggregate(
      from(r in external(actor), where: r.status in ~w(pending approved) and r.expires_at > ^now),
      :count
    )
  end

  defp external(actor) do
    from(r in Record,
      where: is_nil(r.conversation_id) and r.scope == ^Transfer.scope() and r.actor_id == ^user!(actor).id
    )
  end

  @doc """
  Record the actor's approval of exactly `version` of proposal `id`.

  Only a pending, unexpired proposal without problems can be approved, and
  only while its entries and modules are unchanged. The approval is what
  `apply/3` requires; a model cannot approve on the user's behalf.
  """
  @spec approve(Ecto.UUID.t(), integer(), term()) :: {:ok, Proposal.t()} | {:error, String.t()}
  def approve(id, version, actor) do
    Error.protect(fn ->
      record = record!(id, actor)
      reviewable!(record, version, "pending")
      # An entry changed since is reported as such, before the re-check.
      if record.problems == [] do
        proposal = rebuild!(record, actor)
        current!(proposal, actor)
        recheck!(proposal, record, actor)
        ImageReplacement.ready!(proposal.operations)
      end

      {:ok, record} = Repo.transaction(fn -> approve!(id, version, actor) end)
      rebuild!(record, actor)
    end)
  end

  # The operations are checked again as a proposal is approved and applied:
  # one stored before a check was added or tightened would otherwise keep its
  # old, empty list. Problems found are stored, so the review shows what to
  # resolve, and an approval is withdrawn.
  defp recheck!(proposal, record, actor) do
    case operation_problems(proposal, actor) do
      [] ->
        :ok

      problems ->
        # Only the version and status checked: a proposal cancelled or
        # replaced meanwhile stays so.
        Repo.update_all(
          from(r in Record,
            where: r.id == ^record.id and r.version == ^record.version and r.status == ^record.status
          ),
          set: [problems: Enum.map(problems, &encode_problem/1), status: "pending", approved_at: nil]
        )

        Error.fail!(recheck_failed(problems))
    end
  end

  # A translation's source changed since the proposal was prepared: as for
  # an entry that changed, the proposal is stale, and the message names the
  # units.
  defp recheck_failed(problems) do
    case for(%{code: :source_changed, key: key} <- problems, uniq: true, do: key) do
      [] ->
        dgettext("content_proposals", "Resolve every blocking problem before applying.")

      keys ->
        dgettext(
          "content_proposals",
          "The source of a translation changed after this proposal was prepared, in %{units}. Translate those texts again.",
          units: Enum.join(keys, ", ")
        )
    end
  end

  defp approve!(id, version, actor) do
    record = record!(id, actor, lock: true)
    reviewable!(record, version, "pending")

    if record.problems != [],
      do: Error.fail!(dgettext("content_proposals", "Resolve every blocking problem before applying."))

    record |> rebuild!(actor) |> current!(actor)

    record
    |> Changeset.change(status: "approved", approved_at: DateTime.utc_now())
    |> Repo.update!()
  end

  @doc """
  Leave the operations at `indices` out of `version` of proposal `id`, as the
  reviewer asks: the rest is prepared and stored as the next version, which
  supersedes this one. Nothing is left out of a proposal that is no longer
  under review, and a proposal is not left empty — it is discarded instead.
  """
  @spec leave_out(Ecto.UUID.t(), integer(), [non_neg_integer()], term()) :: {:ok, Proposal.t()} | {:error, String.t()}
  def leave_out(id, version, indices, actor) do
    with {:ok, record} <- Error.protect(fn -> under_review!(id, version, actor) end),
         {:ok, operations} <- Codec.decode_all(record.operations) do
      operations
      |> remaining_operations(indices)
      |> propose_remaining(record, id, actor)
    end
  end

  defp remaining_operations(operations, indices) do
    for {op, index} <- Enum.with_index(operations), index not in indices, do: op
  end

  defp propose_remaining([], _record, _id, _actor),
    do: {:error, dgettext("content_proposals", "Nothing would be left. Discard the proposal instead.")}

  defp propose_remaining(rest, record, id, actor), do: propose(rest, actor, supersedes: id, summary: record.summary)

  defp under_review!(id, version, actor) do
    record = record!(id, actor)

    if record.version != version or record.status not in ~w(pending approved),
      do: Error.fail!(dgettext("content_proposals", "This proposal is no longer under review."))

    record
  end

  @doc """
  Undo an applied proposal: each entry it changed goes back to the revision
  it was at before, and each entry it created is deleted.

  Refused, with nothing changed, when an entry has been edited since the
  proposal was applied — undo would overwrite that work — or when an entry
  has no revision to go back to.
  """
  @spec undo(Ecto.UUID.t(), term()) :: {:ok, Receipt.t()} | {:error, String.t()}
  def undo(id, actor) do
    {source, details} = activity_source(id, actor)

    Brando.Activity.with_proposal(source, Map.put(details, "undo_proposal", true), id, actor, fn -> do_undo(id, actor) end)
  end

  defp do_undo(id, actor) do
    Error.protect(fn ->
      record = record!(id, actor)
      user = user!(actor)
      receipt = receipt(id, actor)

      ensure_undoable!(record, receipt)
      saved = saved_entries(receipt)
      ensure_unchanged_since_apply!(saved, actor)
      ensure_revisions!(saved, receipt)

      {:ok, receipt} = Repo.transaction(fn -> undo_saved!(saved, record, receipt, user) end)

      receipt
    end)
  end

  defp ensure_undoable!(record, receipt) do
    cond do
      record.status == "undone" ->
        Error.fail!(dgettext("content_proposals", "This proposal has already been undone."))

      record.status != "applied" or is_nil(receipt) ->
        Error.fail!(dgettext("content_proposals", "Only an applied proposal can be undone."))

      replaced_images?(receipt) ->
        Error.fail!(
          dgettext("content_proposals", "This proposal replaced an image's file, and a replaced file cannot be undone.")
        )

      true ->
        :ok
    end
  end

  @doc "Whether the proposal of `receipt` replaced an image's file: such a proposal has no undo."
  @spec replaced_images?(Receipt.t() | nil) :: boolean()
  def replaced_images?(%Receipt{mappings: mappings}), do: (mappings || %{})["replaced_images"] not in [nil, []]
  def replaced_images?(_receipt), do: false

  defp saved_entries(receipt) do
    for {key, %{"schema" => name, "id" => entry_id, "fingerprint" => fingerprint}} <- receipt.after do
      {:ok, schema} = Codec.schema(name)
      {key, schema, entry_id, fingerprint}
    end
  end

  defp ensure_unchanged_since_apply!(saved, actor) do
    changed =
      for {_key, schema, entry_id, fingerprint} <- saved,
          entry = load!({schema, entry_id}, actor),
          not Transfer.entry_fingerprint?(entry, fingerprint),
          do: Catalog.describe(entry).title

    if changed != [],
      do:
        Error.fail!(
          dgettext("content_proposals", "%{entries} changed after the proposal was applied. Undo would overwrite that.",
            entries: Enum.join(changed, ", ")
          )
        )
  end

  defp ensure_revisions!(saved, receipt) do
    without_revision =
      for {key, _schema, _id, _} <- saved,
          !String.starts_with?(key, "new:"),
          is_nil(receipt.before[key]["revision"]),
          do: key

    if without_revision != [],
      do: Error.fail!(dgettext("content_proposals", "An entry has no earlier revision to go back to."))
  end

  defp undo_saved!(saved, record, receipt, user) do
    Enum.each(saved, &undo_entry!(&1, receipt, user))
    delete_emptied_groups!(receipt)

    record |> Changeset.change(status: "undone") |> Repo.update!()

    receipt
    |> Changeset.change(mappings: Map.put(receipt.mappings, "undone_at", DateTime.to_iso8601(DateTime.utc_now())))
    |> Repo.update!()
  end

  defp undo_entry!({"new:" <> ref, schema, entry_id, _}, receipt, user) do
    case receipt.mappings["translations"][ref] do
      nil -> delete_entry!(schema, entry_id, user)
      group -> delete_translation!(schema, entry_id, group, user)
    end
  end

  # A translation's answered work is opened again once its text is back.
  defp undo_entry!({key, schema, entry_id, _}, receipt, user) do
    restore!(schema, entry_id, receipt.before[key]["revision"], user)

    case (receipt.mappings["translated"] || %{})[key] do
      [_ | _] = items -> {:ok, _} = Translations.reopen_work(schema, entry_id, items)
      _ -> :ok
    end
  end

  # The translation leaves its group, and its alternate link goes with it. A
  # version that joined the group since keeps it, with its pending version
  # and work.
  #
  # The group is locked as a source save's synchronization locks it. A
  # translation made the group's source since the apply is not deleted: the
  # group would be left without one. Making it the source does not take the
  # group's lock, so the member is deleted only while it is still a target.
  defp delete_translation!(schema, entry_id, group, user) do
    group_id = group["group_id"]
    Repo.one(from(g in Translations.Group, where: g.id == ^group_id, lock: "FOR UPDATE"))

    own =
      from(m in Translations.Member,
        where: m.group_id == ^group_id and m.entry_type == ^to_string(schema) and m.entry_id == ^entry_id
      )

    {deleted, _} = Repo.delete_all(from(m in own, where: m.role == :target))
    if deleted == 0 and Repo.one(from(m in own, select: count())) > 0, do: Error.fail!(became_source(schema, entry_id))

    if schema.has_alternates?(), do: Module.concat(schema, Alternate).delete(group["source_id"], entry_id)
    delete_entry!(schema, entry_id, user)
  end

  # A group the apply made goes when only its source is left, so the source
  # is as it was and its languages are free again. Decided once every
  # translation is undone: one proposal can create several versions, and only
  # the first is recorded as having made the group.
  defp delete_emptied_groups!(receipt) do
    for {_ref, %{"new_group" => true, "group_id" => group_id}} <- receipt.mappings["translations"] || %{},
        match?([%{role: :source}], Translations.list_members(group_id)),
        do: Repo.delete_all(from(g in Translations.Group, where: g.id == ^group_id))

    :ok
  end

  defp became_source(schema, entry_id) do
    dgettext(
      "content_proposals",
      "%{entry} became its translation group's source after the proposal was applied. Undo would leave the group without a source: make another version the source first.",
      entry: Catalog.describe(Repo.get!(schema, entry_id)).title
    )
  end

  defp restore!(schema, id, revision, user) do
    case Brando.Revisions.set_entry_to_revision(schema, id, revision, user) do
      {:ok, _entry} -> :ok
      {:error, reason} -> Error.fail!(dgettext("content_proposals", "Undo failed: %{reason}", reason: inspect(reason)))
    end
  end

  defp delete_entry!(schema, id, user) do
    context = schema.__modules__().context
    singular = schema.__naming__().singular

    case Kernel.apply(context, :"delete_#{singular}", [id, user]) do
      {:ok, _} -> :ok
      {:error, reason} -> Error.fail!(dgettext("content_proposals", "Undo failed: %{reason}", reason: inspect(reason)))
    end
  end

  @doc """
  Load `version` of proposal `id` for a colleague it was shared with, to
  review it read-only. The viewer must be able to read its entries, and the
  images it replaces files of (`ImageReplacement.readable!/3`); only the
  proposing user can approve and apply it.
  """
  @spec get_shared(Ecto.UUID.t(), integer(), term()) :: {:ok, Proposal.t()} | {:error, String.t()}
  def get_shared(id, version, viewer) do
    Error.protect(fn ->
      Transfer.ensure_scope!(viewer)

      record =
        Repo.one(from(r in Record, where: r.id == ^id and r.scope == ^Transfer.scope() and r.version == ^version)) ||
          Error.fail!(dgettext("content_proposals", "This proposal is no longer available."))

      if record.status not in ~w(pending approved applied),
        do: Error.fail!(dgettext("content_proposals", "This proposal is no longer under review."))

      proposal = rebuild!(record, viewer, :read)
      ImageReplacement.readable!(proposal.operations, viewer, record.status == "applied")
      proposal
    end)
  end

  @share_salt "brando-proposal-share"

  @doc """
  A token that lets colleagues review `version` of proposal `id` for a day:
  all of its entries, or only those with the given keys.
  """
  @spec share_token(Proposal.t(), [String.t()] | nil) :: String.t()
  def share_token(%Proposal{id: id, version: version}, keys \\ nil) do
    payload = %{"id" => id, "version" => version}
    payload = if keys, do: Map.put(payload, "keys", keys), else: payload
    Phoenix.Token.sign(Brando.endpoint(), @share_salt, payload)
  end

  @doc """
  The proposal id and version a share token names, while it is valid, and
  the keys of the entries it shows (`nil` for all).
  """
  @spec verify_share_token(String.t()) ::
          {:ok, {Ecto.UUID.t(), integer(), [String.t()] | nil}} | {:error, atom()}
  def verify_share_token(token) do
    case Phoenix.Token.verify(Brando.endpoint(), @share_salt, token, max_age: div(@ttl, 1000)) do
      {:ok, %{"id" => id, "version" => version} = payload} -> {:ok, {id, version, payload["keys"]}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Cancel a proposal under review. Content is untouched."
  @spec cancel(Ecto.UUID.t(), term()) :: :ok | {:error, String.t()}
  def cancel(id, actor) do
    with {:ok, _} <- Error.protect(fn -> cancel!(record!(id, actor)) end), do: :ok
  end

  defp cancel!(%Record{status: status} = record) when status in ~w(pending approved),
    do: record |> Changeset.change(status: "cancelled") |> Repo.update!()

  defp cancel!(record), do: record

  @doc """
  Whether `cancel/2` would discard proposal `id` for the actor: it is the
  actor's, in this site/environment, and under review. Its operations are not
  read, so a proposal that can no longer be loaded for review, such as one
  stored naming a content type the catalogue does not list, can be discarded.
  """
  @spec discardable?(Ecto.UUID.t(), term()) :: boolean()
  def discardable?(id, actor) do
    case Error.protect(fn -> record!(id, actor) end) do
      {:ok, %Record{status: status}} -> status in ~w(pending approved)
      {:error, _} -> false
    end
  end

  @doc """
  Apply the approved `version` of proposal `id` atomically and return its receipt.

  Entries are locked and compared with the proposal's fingerprints; a changed
  entry or module aborts without writing. Applying an applied proposal again
  returns its receipt.
  """
  @spec apply(Ecto.UUID.t(), integer(), term()) :: {:ok, Receipt.t()} | {:error, String.t()}
  def apply(id, version, actor, opts \\ []) do
    {source, details} = activity_source(id, actor)
    Brando.Activity.with_proposal(source, details, id, actor, fn -> do_apply(id, version, actor, opts) end)
  end

  # The activity log says who prepared the change: the Assistant, or a tool
  # connected over MCP, by name when it is known; which proposal it came
  # from; and the reviewer who approved and applied it (or undid it).
  defp activity_source(id, actor) do
    case Error.protect(fn -> record!(id, actor) end) do
      {:ok, %Record{origin: "mcp", client: nil}} -> {:mcp, %{}}
      {:ok, %Record{origin: "mcp", client: client}} -> {:mcp, %{"client" => client}}
      _ -> {:assistant, %{}}
    end
  end

  defp do_apply(id, version, actor, opts) do
    result =
      Error.protect(fn ->
        record = record!(id, actor)

        if record.status == "applied" do
          {receipt(id, actor), []}
        else
          reviewable!(record, version, "approved")
          proposal = rebuild!(record, actor)
          current!(proposal, actor)
          recheck!(proposal, record, actor)
          apply!(proposal, actor, opts)
        end
      end)

    with {:ok, {receipt, saved}} <- result do
      ImageReplacement.after_commit(receipt.mappings["replaced_images"] || [])
      Enum.each(saved, &after_apply(&1, actor))
      {:ok, receipt}
    end
  end

  # What follows an editor's save, once the proposal is committed: the
  # traits' after-save work, then notifications and broadcasts. The sync of
  # synchronized translations was queued by the context mutation that saved
  # the entry.
  # A translation is made as the admin makes it, without an after-save.
  defp after_apply({target, entry, nil}, actor), do: announce({target, entry}, actor)

  defp after_apply({target, entry, changeset}, actor) do
    try do
      Brando.Blueprint.AfterSave.run(entry.__struct__, entry, changeset, user!(actor))
    rescue
      error -> require(Logger) && Logger.error("After-save of an applied proposal failed: " <> Exception.message(error))
    end

    announce({target, entry}, actor)
  end

  defp reviewable!(record, version, status) do
    cond do
      record.version != version or record.status == "superseded" ->
        Error.fail!(dgettext("content_proposals", "A newer version of this proposal exists. Review it instead."))

      record.status != status and status == "approved" ->
        Error.fail!(dgettext("content_proposals", "Approve this version of the proposal before applying it."))

      record.status != status ->
        Error.fail!(dgettext("content_proposals", "This proposal is no longer under review."))

      DateTime.compare(record.expires_at, DateTime.utc_now()) == :lt ->
        Error.fail!(dgettext("content_proposals", "This proposal has expired. Prepare it again."))

      true ->
        :ok
    end
  end

  defp record!(id, actor, opts \\ []) do
    query =
      from(r in Record,
        where: r.id == ^id and r.scope == ^Transfer.scope() and r.actor_id == ^user!(actor).id
      )

    query = if opts[:lock], do: from(r in query, lock: "FOR UPDATE"), else: query

    Repo.one(query) ||
      Error.fail!(dgettext("content_proposals", "This proposal belongs to another user, site or environment."))
  rescue
    Ecto.Query.CastError ->
      Error.fail!(dgettext("content_proposals", "This proposal belongs to another user, site or environment."))
  end

  defp rebuild!(record, actor, action \\ :update) do
    # A stored operation naming a content type the catalogue no longer
    # lists (or never did) is refused, not reviewed or applied.
    operations =
      case Codec.decode_all(record.operations) do
        {:ok, operations} -> operations
        {:error, message} -> Error.fail!(message)
      end

    creates = creates(operations)

    entries =
      for op <- operations,
          target <- op_targets(op),
          match?({schema, id} when schema != :new and is_integer(id), target),
          uniq: true,
          into: %{},
          do: {target, load!(target, actor, action: action)}

    entries = baseline(record, entries)

    proposal = %Proposal{
      id: record.id,
      scope: record.scope,
      actor_id: record.actor_id,
      operations: operations,
      targets: Map.merge(entries, creates),
      fingerprints: Map.new(entries, fn {target, _} -> {target, record.fingerprints[Proposal.key(target)]} end),
      module_versions:
        Map.new(record.module_versions, fn %{"origin" => origin, "id" => id, "version" => version} ->
          {Content.SharedLibrary.reference("#{origin}:#{id}"), version}
        end),
      problems: Enum.map(record.problems, &decode_problem/1)
    }

    effects = decode_effects(record.effects, Map.keys(proposal.targets), sources(operations))
    with_record(%{proposal | effects: effects}, record)
  end

  # An applied or undone proposal is reviewed against the entries as they
  # were when it was applied, from its receipt. Against the entries as they
  # are now, each change would show again on top of its own result. The
  # entries are still loaded above: reading them is what authorizes the
  # review.
  defp baseline(%Record{status: status} = record, entries) when status in ~w(applied undone) do
    case Repo.one(from(r in Receipt, where: r.id == ^record.id and r.scope == ^record.scope)) do
      %Receipt{before: before} ->
        Map.new(entries, fn {target, entry} ->
          {target, Baseline.load(entry, get_in(before, [Proposal.key(target), "entry"]))}
        end)

      nil ->
        entries
    end
  end

  defp baseline(_record, entries), do: entries

  defp with_record(proposal, record) do
    %{
      proposal
      | version: record.version,
        status: record.status,
        conversation_id: record.conversation_id,
        summary: record.summary,
        origin: record.origin,
        client: record.client,
        supersedes_id: record.supersedes_id,
        expires_at: record.expires_at
    }
  end

  defp encode_problem(problem) do
    problem
    |> Map.update(:target, nil, &(&1 && Proposal.key(&1)))
    |> Map.new(fn {key, value} -> {to_string(key), if(key == :code, do: to_string(value), else: value)} end)
  end

  defp decode_problem(problem) do
    %{
      code: String.to_existing_atom(problem["code"]),
      message: problem["message"],
      operation: problem["operation"],
      target: problem["target"],
      key: problem["key"]
    }
  end

  # Effects stored since entries only copied from stopped counting as updated
  # say so; the counts of older ones are corrected as they are read.
  defp encode_effects(effects) do
    effects
    |> Map.new(fn
      {:live, targets} -> {"live", Enum.map(targets, &Proposal.key/1)}
      {key, value} -> {to_string(key), value}
    end)
    |> Map.put("sources_excluded", true)
  end

  defp decode_effects(effects, targets, sources) do
    stale = if effects["sources_excluded"], do: [], else: Enum.filter(sources, &(&1 in targets))
    live = Enum.filter(targets -- stale, &(Proposal.key(&1) in (effects["live"] || [])))

    %{
      creates: effects["creates"],
      updates: effects["updates"] && max(effects["updates"] - length(stale), 0),
      inserted_blocks: effects["inserted_blocks"],
      updated_blocks: effects["updated_blocks"],
      moved_blocks: effects["moved_blocks"] || 0,
      deletions: effects["deletions"],
      replaced_images: effects["replaced_images"] || 0,
      live: live
    }
  end

  defp apply!(proposal, actor, opts) do
    authorize_proposal!(proposal, actor)

    if proposal.problems != [],
      do: Error.fail!(dgettext("content_proposals", "Resolve every blocking problem before applying."))

    case receipt(proposal.id, actor) do
      %Receipt{} = receipt -> {receipt, []}
      nil -> apply_new!(proposal, actor, opts)
    end
  end

  defp apply_new!(proposal, actor, opts) do
    {:ok, result} =
      Repo.transaction(fn ->
        Ecto.Adapters.SQL.query!(Repo.repo(), "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
          "brando-content-proposal:" <> Transfer.scope()
        ])

        case receipt(proposal.id, actor) do
          %Receipt{} = receipt -> {receipt, []}
          nil -> apply_locked!(proposal, actor, user!(actor), opts)
        end
      end)

    result
  end

  defp apply_locked!(proposal, actor, user, opts) do
    record = record!(proposal.id, actor, lock: true)
    publish = publish_targets!(proposal, actor, opts[:publish] || [])

    unless record.status == "approved" and record.version == proposal.version,
      do: Error.fail!(dgettext("content_proposals", "Approve this version of the proposal before applying it."))

    locked =
      for target <- apply_lock_order(proposal),
          entry = lock_target!(target, proposal, actor),
          do: entry

    Transfer.lock_records!(%{fields: Enum.map(locked, &%{entry: &1}), bindings: %{}})
    entries = current!(proposal, actor)
    check_translated_sources!(proposal)
    # The revision each entry is at now: undo restores it.
    revisions = Map.new(entries, fn {target, entry} -> {target, revision_before(target, entry, user)} end)

    # Before the entries are saved, so what they render shows the new file.
    replaced =
      for %ReplaceImageFile{} = op <- proposal.operations,
          do: ImageReplacement.apply!(op, proposal.operations, actor, user)

    # An entry blocks are only copied from is not saved, unless it is
    # published as the proposal is applied.
    unchanged = Enum.reject(sources(proposal.operations), &(Proposal.key(&1) in publish))

    translations = for %CreateTranslation{} = op <- proposal.operations, do: {{:new, op.ref}, op}

    # A translation `Translate` fills in is saved as its form saves it.
    translated = translated_targets(proposal)

    # Create first: later stages resolve `{:new, ref}` to the saved id.
    # Otherwise entries are saved in the order the operations name them.
    # A translation is created in its turn among the creates.
    {saved, {groups, resolved}} =
      proposal
      |> materialize!(entries, user)
      |> Enum.reject(fn {target, _cs} -> target in unchanged or List.keymember?(translated, target, 0) end)
      |> Enum.map(fn {target, cs} ->
        if Proposal.key(target) in publish,
          do: {target, Changeset.put_change(cs, :status, :published)},
          else: {target, cs}
      end)
      |> Enum.concat(translations)
      |> Enum.concat(translated)
      |> Enum.sort_by(fn {target, _} -> {!match?({:new, _}, target), first_mention(proposal, target)} end)
      |> Enum.map_reduce({%{}, %{}}, &save_target!(&1, &2, proposal, user))

    receipt =
      Repo.insert!(%Receipt{
        id: proposal.id,
        version: proposal.version,
        scope: proposal.scope,
        actor_id: user.id,
        before: Map.new(entries, &snapshot(&1, proposal, revisions)),
        after: Map.new(saved, fn {target, entry, _cs} -> saved_fingerprint({target, entry}, actor) end),
        mappings: %{
          "created" => for({{:new, ref}, entry, _cs} <- saved, into: %{}, do: {ref, entry.id}),
          "translations" => groups,
          # The work items each translation's save resolved, opened again by undo
          "translated" => Map.new(resolved, fn {key, items} -> {key, Enum.map(items, &stored_item/1)} end),
          "published" => publish,
          "effects" => encode_effects(proposal.effects),
          "replaced_images" => replaced
        }
      })

    record |> Changeset.change(status: "applied") |> Repo.update!()
    {receipt, saved}
  end

  @doc """
  The rows an apply locks first, as `{schema, id}`, sorted as
  `Brando.Content.Transfer.lock_records!/1` sorts them: the proposal's
  entries and the sources its `translate` operations translate.

  Sources are read from their group's members, without refreshing a
  translation's pending version, which takes the group lock: a source locked
  after that, or after the entries, could deadlock with a transfer import or
  a Create translation that locks the source first.
  """
  @spec apply_lock_order(Proposal.t()) :: [{module(), pos_integer()}]
  def apply_lock_order(proposal) do
    proposal.fingerprints
    |> Map.keys()
    |> Enum.concat(translated_sources(proposal))
    |> Enum.uniq()
    |> Enum.sort_by(fn {schema, id} -> {to_string(schema), id} end)
  end

  defp translated_sources(proposal) do
    for %Translate{target: target} <- proposal.operations, source = translated_source(target, proposal), do: source
  end

  defp translated_source({:new, _} = target, proposal) do
    case translation(proposal.operations, target) do
      %CreateTranslation{source: {_schema, id} = source} when is_integer(id) -> source
      _ -> nil
    end
  end

  defp translated_source({schema, id}, _proposal) do
    with %{role: :target, group_id: group_id} <- Translations.get_member(schema, id),
         %{entry_id: source_id} <- Enum.find(Translations.list_members(group_id), &(&1.role == :source)) do
      {schema, source_id}
    else
      _ -> nil
    end
  end

  # An entry the proposal changes is loaded under its lock; a source it
  # only translates from is locked, and read again by the check.
  defp lock_target!(target, proposal, actor) do
    if Map.has_key?(proposal.fingerprints, target) do
      load!(target, actor, lock: true)
    else
      {schema, id} = target
      lock_source!(schema, id)
      nil
    end
  end

  @doc """
  Checks every `translate` batch of `proposal` against its source again,
  under the source's lock, and raises a transfer error naming
  the units whose source text changed.

  Called inside the apply's transaction, before any translation is created
  or saved: a source saved after the recheck at approval would otherwise
  have its new text overwritten by the translation of the text before.
  """
  @spec check_translated_sources!(Proposal.t()) :: :ok
  def check_translated_sources!(proposal) do
    problems =
      for %Translate{} = op <- proposal.operations,
          problem <- translated_source_problems(op, proposal),
          do: problem

    if problems != [], do: Error.fail!(recheck_failed(problems))
    :ok
  end

  defp translated_source_problems(%Translate{target: {:new, _} = target} = op, proposal) do
    %CreateTranslation{source: {schema, source_id}, language: language} = translation(proposal.operations, target)
    lock_source!(schema, source_id)

    case Work.new_translation_units(schema, source_id) do
      {:ok, %{units: units}} ->
        source_check(op, %{type: to_string(schema), id: {:new, source_id}, language: language}, units)

      {:error, _} ->
        Error.fail!(dgettext("content_proposals", "The source of this translation is not available to you."))
    end
  end

  # The apply locked the source already (`apply_lock_order/1`); locking it
  # again, before the work is read, holds when the check runs on its own.
  defp translated_source_problems(%Translate{target: {schema, id} = target} = op, proposal) do
    with {source_schema, source_id} <- translated_source(target, proposal),
         do: lock_source!(source_schema, source_id)

    case Work.translation_units(schema, id) do
      {:ok, work} -> source_check(op, %{type: to_string(schema), id: id, language: work.language}, work.units)
      {:error, reason} -> Error.fail!(not_a_translation(reason).message)
    end
  end

  defp lock_source!(schema, source_id) do
    Repo.one(from(e in schema, where: e.id == ^source_id, select: e.id, lock: "FOR UPDATE"))
    :ok
  end

  defp source_check(op, scope, units) do
    case Work.check(op.source_digest, scope, units, %{texts: op.texts, reviewed: op.reviewed}) do
      :ok -> []
      {:error, problems} -> Enum.map(problems, &work_problem(&1, units))
    end
  end

  defp translated_targets(proposal) do
    for {{schema, id} = target, _} <- proposal.targets,
        is_integer(id),
        translated?(proposal.operations, target),
        do: {target, {:translate, schema, id}}
  end

  # One entry of the apply, in its turn. `groups` holds the translation
  # groups created translations joined, `resolved` the work items each
  # translated entry's save resolved.
  defp save_target!({{:new, ref} = target, %CreateTranslation{} = op}, {groups, resolved}, proposal, user) do
    {entry, group} = create_translation!(op, user)
    groups = Map.put(groups, ref, group)

    # Created first, then filled in, in the same transaction
    if translated?(proposal.operations, target) do
      result = save_translation!(elem(op.source, 0), entry.id, proposal, target, user)
      {{target, result.entry, nil}, {groups, Map.put(resolved, Proposal.key(target), result.resolved)}}
    else
      {{target, entry, nil}, {groups, resolved}}
    end
  end

  defp save_target!({target, {:translate, schema, id}}, {groups, resolved}, proposal, user) do
    result = save_translation!(schema, id, proposal, target, user)
    {{target, result.entry, result.changeset}, {groups, Map.put(resolved, Proposal.key(target), result.resolved)}}
  end

  defp save_target!({target, cs} = pair, acc, _proposal, user) do
    {^target, entry} = save!(pair, user)
    {{target, entry, cs}, acc}
  end

  # The translation form's save (`Translations.save_work/5`), inside the
  # apply's transaction: every batch's texts written into its pending
  # version, and every answered item resolved.
  defp save_translation!(schema, id, proposal, target, user) do
    case Translations.save_work(schema, id, translated_answer(proposal, target), user,
           mutation: [show_notification: false, pubsub: false]
         ) do
      {:ok, result} -> result
      {:error, reason} -> Error.fail!(translate_failed(reason))
    end
  end

  defp stored_item(item), do: Map.new(item, fn {key, value} -> {to_string(key), stored_value(value)} end)

  defp stored_value(value) when is_atom(value) and not is_boolean(value) and not is_nil(value), do: to_string(value)
  defp stored_value(value), do: value

  # Publishing is the reviewer's choice at apply, per entry: new entries are
  # drafts otherwise, and drafts stay drafts. It takes the publish permission.
  defp publish_targets!(proposal, actor, keys) do
    keys = Enum.map(keys, &to_string/1)

    for key <- keys do
      target = Enum.find(Map.keys(proposal.targets), &(Proposal.key(&1) == key))
      schema = target && proposal_schema(proposal, target)

      cond do
        is_nil(schema) or not schema.has_trait(Brando.Trait.Status) or translation(proposal.operations, target) != nil or
            translated?(proposal.operations, target) ->
          Error.fail!(dgettext("content_proposals", "Only entries in this proposal that have a status can be published."))

        Boundary.authorize(actor, :publish, schema) != :ok ->
          Error.fail!(dgettext("content_proposals", "You do not have permission to publish this entry."))

        true ->
          key
      end
    end
  end

  # The editor's Create translation, inside the apply's transaction and lock:
  # `create_target/5` nests its own transaction in it, so a refusal here, or a
  # failure later in the apply, rolls the whole apply back. The checks run
  # again first, as the language may have been taken since the proposal was
  # approved. Returns the translation and its group, with whether this apply
  # made the group, for undo.
  defp create_translation!(%CreateTranslation{source: {schema, id}, language: language}, user) do
    had_group? = Translations.get_member(schema, id) != nil

    case Translations.create_target(schema, id, language, user) do
      {:ok, entry} ->
        %{group_id: group_id} = Translations.get_member(schema, entry.id)
        {entry, %{"group_id" => group_id, "new_group" => !had_group?, "source_id" => id}}

      {:error, reason} ->
        Error.fail!(translation_failed(reason))
    end
  end

  defp translation_failed(:language_exists),
    do: dgettext("content_proposals", "The source already has a version in this language. Change that version instead.")

  defp translation_failed(:not_source),
    do: dgettext("content_proposals", "This entry is a translation. Create translations from its group's source.")

  defp translation_failed(:forbidden),
    do: dgettext("content_proposals", "You do not have permission to create a translation of this entry.")

  defp translation_failed(%Changeset{} = changeset),
    do:
      dgettext("content_proposals", "Entry validation: %{errors}",
        errors: inspect(Changeset.traverse_errors(changeset, fn {message, _} -> message end))
      )

  defp translation_failed(reason),
    do: dgettext("content_proposals", "The translation could not be created: %{reason}", reason: inspect(reason))

  defp proposal_schema(_proposal, {schema, id}) when is_integer(id), do: schema
  defp proposal_schema(proposal, target), do: Map.get(proposal.targets, target)

  # An entry never saved with a revision gets one of its state now, so undo
  # has something to go back to.
  defp revision_before(target, entry, user) do
    case active_revision(target) do
      nil ->
        with true <- elem(target, 0).has_trait(Brando.Trait.Revisioned),
             {:ok, revision} <- Brando.Revisions.create_revision(entry, user) do
          revision.revision
        else
          _ -> nil
        end

      number ->
        number
    end
  end

  defp active_revision({schema, id}) do
    if schema.has_trait(Brando.Trait.Revisioned) do
      case Brando.Revisions.get_active_revision(schema, id) do
        {:ok, {_revision, {number, _entry}}} -> number
        _ -> nil
      end
    end
  rescue
    _ -> nil
  end

  defp snapshot({target, entry}, proposal, revisions) do
    {Proposal.key(target),
     %{
       "fingerprint" => proposal.fingerprints[target],
       "entry" => Params.snapshot(entry),
       "revision" => revisions[target]
     }}
  end

  defp saved_fingerprint({target, entry}, actor) do
    entry = load!({entry.__struct__, entry.id}, actor)

    {Proposal.key(target),
     %{"schema" => to_string(entry.__struct__), "id" => entry.id, "fingerprint" => Transfer.entry_fingerprint(entry)}}
  end

  defp first_mention(proposal, target) do
    Enum.find_index(proposal.operations, fn
      %type{ref: ref} when type in [CreateEntry, CreateTranslation] -> {:new, ref} == target
      op -> target in op_targets(op)
    end)
  end

  # A collision would otherwise be renamed on save, so the saved key would
  # differ from the reviewed one. Notifications and mutation broadcasts are
  # suppressed inside the transaction and sent once the content is committed.
  defp save!({target, changeset}, user) do
    Transfer.Entries.unique!(changeset)

    schema = changeset.data.__struct__
    context = schema.__modules__().context
    singular = schema.__naming__().singular

    result =
      case target do
        {:new, _} -> Kernel.apply(context, :"create_#{singular}", [changeset, user, [notify?: false, pubsub?: false]])
        _ -> Kernel.apply(context, :"update_#{singular}", [changeset, user, [show_notification: false, pubsub: false]])
      end

    case result do
      {:ok, entry} ->
        {target, entry}

      {:error, %Changeset{} = cs} ->
        Error.fail!(
          dgettext("content_proposals", "Entry validation: %{errors}",
            errors: inspect(Changeset.traverse_errors(cs, fn {message, _} -> message end))
          )
        )

      {:error, _} ->
        Error.fail!(dgettext("content_proposals", "You do not have permission to save this entry."))
    end
  end

  defp announce({target, entry}, actor) do
    action = if match?({:new, _}, target), do: :created, else: :updated
    schema = entry.__struct__

    # Editors with the entry open get the applied blocks as ordinary ops,
    # their own unsaved work kept, instead of a stale editor.
    if action == :updated, do: Brando.EditSession.sync_saved(entry)

    Phoenix.PubSub.broadcast(
      Brando.pubsub(),
      Brando.Tenant.Topic.scoped("brando:mutations:#{inspect(schema)}"),
      {:mutation, schema, entry, action}
    )

    if identifier = Brando.Blueprint.Identifier.identifier_for(entry),
      do: Brando.Notifications.push_mutation(Gettext.gettext(Brando.Gettext, to_string(action)), identifier, user!(actor))
  end

  @doc "The receipt of an applied proposal, if the actor applied it in this site/environment."
  @spec receipt(Ecto.UUID.t(), term()) :: Receipt.t() | nil
  def receipt(id, actor) do
    Repo.one(from(r in Receipt, where: r.id == ^id and r.scope == ^Transfer.scope() and r.actor_id == ^user!(actor).id))
  end

  ## Shared

  @doc """
  Raise unless `actor` prepared `proposal` in the current site/environment.
  """
  @spec authorize_proposal!(Proposal.t(), term()) :: :ok
  def authorize_proposal!(proposal, actor) do
    Transfer.ensure_scope!(actor)

    unless proposal.scope == Transfer.scope() && proposal.actor_id == user!(actor).id,
      do: Error.fail!(dgettext("content_proposals", "This proposal belongs to another user, site or environment."))

    :ok
  end

  @doc """
  Load the proposal's existing entries as they are now. Raises if one differs
  from the baseline `prepare/2` captured, or a module a block is built from
  has a new version.
  """
  @spec current!(Proposal.t(), term()) :: %{Proposal.target() => struct()}
  def current!(proposal, actor, action \\ :update) do
    entries = Map.new(proposal.fingerprints, fn {target, _} -> {target, load!(target, actor, action: action)} end)

    unless Enum.all?(entries, fn {target, entry} -> Transfer.entry_fingerprint?(entry, proposal.fingerprints[target]) end),
           do:
             Error.fail!(
               dgettext("content_proposals", "Content changed after this proposal was prepared. Review it again.")
             )

    unless module_versions(proposal.operations) == proposal.module_versions,
      do:
        Error.fail!(dgettext("content_proposals", "A module changed after this proposal was prepared. Review it again."))

    entries
  end

  defp load!({schema, id}, actor, opts \\ []),
    do: Catalog.load!(schema, id, actor, Keyword.get(opts, :action, :update), Keyword.delete(opts, :action))

  defp fetch_module(reference) do
    {origin, id} = Content.SharedLibrary.reference(reference)
    Content.fetch_module(id, origin)
  rescue
    _ -> nil
  end

  defp user!(%Brando.Users.User{} = user), do: user
  defp user!(%Brando.Authorization.Scope{user_id: id}) when is_integer(id), do: Repo.get!(Brando.Users.User, id)
  defp user!(_), do: Error.fail!(dgettext("content_proposals", "A proposal requires an authenticated user."))
end
