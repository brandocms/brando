defmodule Brando.Content.Proposals do
  use Gettext, backend: Brando.Gettext

  @moduledoc """
  Reviewed content changes across several saved entries.

  A proposal is a list of semantic operations — `CreateEntry`, `SetFields`,
  `InsertBlock`, `SetBlockMedia`, `SetBlockValues`, `SetBlockText`, `MoveBlock`
  and `DeleteBlock` — that `prepare/2` resolves against the actor's content,
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
  """
  import Ecto.Query, only: [from: 2]
  import Kernel, except: [apply: 3]

  alias Brando.Authorization.Boundary
  alias Brando.Content
  alias Brando.Content.Blocks
  alias Brando.Content.BlockSlots
  alias Brando.Content.Proposals.BlockTree
  alias Brando.Content.Proposals.Codec
  alias Brando.Content.Proposals.CopyBlock
  alias Brando.Content.Proposals.CreateEntry
  alias Brando.Content.Proposals.DeleteBlock
  alias Brando.Content.Proposals.EntryFields
  alias Brando.Content.Proposals.EntryLinks
  alias Brando.Content.Proposals.InsertBlock
  alias Brando.Content.Proposals.MoveBlock
  alias Brando.Content.Proposals.Proposal
  alias Brando.Content.Proposals.Receipt
  alias Brando.Content.Proposals.Record
  alias Brando.Content.Proposals.RefConfig
  alias Brando.Content.Proposals.SetBlockActive
  alias Brando.Content.Proposals.SetBlockDetails
  alias Brando.Content.Proposals.SetBlockMedia
  alias Brando.Content.Proposals.SetBlockSelection
  alias Brando.Content.Proposals.SetBlockTable
  alias Brando.Content.Proposals.SetBlockText
  alias Brando.Content.Proposals.SetBlockValues
  alias Brando.Content.Proposals.SetFields
  alias Brando.Content.Proposals.SetRefConfig
  alias Brando.Content.Transfer
  alias Brando.Content.Transfer.Catalog
  alias Brando.Content.Transfer.Dependencies
  alias Brando.Content.Transfer.Error
  alias Brando.Drafts.Params
  alias Brando.Repo
  alias Brando.Utils
  alias Ecto.Changeset

  @protected_fields ~w(id status publish_at deleted_at marked_as_deleted creator_id inserted_at updated_at)
  @text_vars [:string, :text, :html]
  @media_kinds %{image: "picture", video: "video", gallery: "gallery"}

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
    operations = Enum.map(operations, &(&1 |> freeze() |> EntryLinks.resolve(actor)))
    creates = for %CreateEntry{} = op <- operations, into: %{}, do: {{:new, op.ref}, op.schema}

    entries =
      operations
      |> Enum.flat_map(&op_targets/1)
      |> Enum.filter(&match?({schema, id} when is_atom(schema) and schema != :new and not is_nil(id), &1))
      |> Enum.uniq()
      |> Map.new(fn target -> {target, load!(target, actor)} end)

    proposal = %Proposal{
      id: Ecto.UUID.generate(),
      scope: Transfer.scope(),
      actor_id: user.id,
      operations: operations,
      targets: Map.merge(entries, creates),
      fingerprints: Map.new(entries, fn {target, entry} -> {target, Transfer.entry_fingerprint(entry)} end),
      module_versions: module_versions(operations)
    }

    {problems, _trees} =
      operations
      |> Enum.with_index()
      |> Enum.flat_map_reduce(%{}, fn {op, index}, trees ->
        {problems, trees} = check(op, proposal, actor, trees)
        {copy_problems, trees} = check_copy_destination(op, proposal, trees)
        problems = problems ++ copy_problems ++ link_problems(op)
        {Enum.map(problems, &Map.put(&1, :operation, index)), trees}
      end)

    problems = if problems == [], do: check_changesets(proposal, entries, user), else: problems
    %{proposal | problems: problems, effects: effects(proposal)}
  end

  # The entries an operation touches: its target, and a copy's destination.
  defp op_targets(%CopyBlock{target: target, to_target: to}) when not is_nil(to), do: [target, to]
  defp op_targets(op), do: [Map.get(op, :target)]

  defp freeze(%CreateEntry{} = op), do: %{op | ref: to_string(op.ref), fields: stringify(op.fields)}
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
  defp check_copy_destination(%CopyBlock{to_target: to} = op, proposal, trees) when not is_nil(to) do
    source = {op.target, op.field}
    source_tree = Map.get_lazy(trees, source, fn -> saved_tree(op.target, op.field, proposal) end)
    saved? = saved_block_of(proposal, op.target, op.field, op.block_uid) != nil

    with {:ok, schema} <- target_schema(to, proposal),
         :ok <- block_field(schema, op.to_field),
         %{} = node <- BlockTree.fetch(source_tree, op.block_uid) || {:error, unknown_block()},
         true <- saved? || {:error, copy_unsaved()},
         key = {to, op.to_field},
         tree = Map.get_lazy(trees, key, fn -> saved_tree(to, op.to_field, proposal) end),
         :ok <- new_uid(op.uid, tree),
         {:ok, parent} <- destination(op.placement, %{node | uid: op.uid, parent: nil}, tree, :copy),
         :ok <- movable(%{node | parent: :elsewhere}, parent, schema, op.to_field, tree) do
      {[], Map.put(trees, key, BlockTree.copy_from(source_tree, tree, node.uid, op.uid, parent, op.placement))}
    else
      {:error, problem} -> {[problem], trees}
    end
  end

  defp check_copy_destination(_op, _proposal, trees), do: {[], trees}

  defp copy_unsaved,
    do:
      problem(
        :unknown_block,
        dgettext("content_proposals", "Only a saved block can be copied to another entry or field.")
      )

  defp saved_block_of(proposal, target, field, uid) do
    with %{} = entry <- Map.get(proposal.targets, target),
         {block, _, _} <- BlockTree.find_saved(Map.get(entry, :"entry_#{field}", []), uid) do
      block
    else
      _ -> nil
    end
  end

  defp check(%CreateEntry{} = op, proposal, actor) do
    duplicate? = Enum.count(proposal.operations, &match?(%CreateEntry{ref: ref} when ref == op.ref, &1)) > 1

    cond do
      duplicate? ->
        [problem(:duplicate_ref, dgettext("content_proposals", "Two new entries use the same reference."))]

      op.schema not in Brando.Authorization.Catalog.schemas() ->
        [problem(:unknown_schema, dgettext("content_proposals", "This content type is not registered on this site."))]

      Boundary.authorize(actor, :create, op.schema) != :ok ->
        [problem(:forbidden, dgettext("content_proposals", "You do not have permission to create this entry."))]

      true ->
        protected_fields(op.fields, op.schema) ++
          asset_fields(op.fields, op.schema, actor) ++
          list_fields(op.fields, op.schema, actor) ++ draft_dependencies(op.fields, proposal)
    end
  end

  defp check(%SetFields{target: {:new, _}}, _, _),
    do: [problem(:unknown_target, dgettext("content_proposals", "Set the fields of a new entry when creating it."))]

  defp check(%SetFields{} = op, proposal, actor) do
    {schema, _} = op.target

    protected_fields(op.fields, schema) ++
      asset_fields(op.fields, schema, actor) ++
      list_fields(op.fields, schema, actor) ++ draft_dependencies(op.fields, proposal)
  end

  defp saved_tree(target, field, proposal) do
    case Map.get(proposal.targets, target) do
      %{} = entry -> entry |> Map.fetch!(:"entry_#{field}") |> BlockTree.from_saved()
      _ -> %BlockTree{}
    end
  end

  defp check_block(%InsertBlock{} = op, schema, tree, actor, proposal) do
    with :ok <- new_uid(op.uid, tree),
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
      {:error, problem} -> {[problem], tree}
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
  defp check_block(%CopyBlock{} = op, schema, tree, _actor, _proposal) do
    with {:ok, node} <- structural_block(tree, op.block_uid),
         :ok <- new_uid(op.uid, tree),
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
      nil -> ref_exists(name, module)
      definition -> Enum.map(RefConfig.problems(name, definition, config), &problem(:unsupported_value, &1))
    end
  end

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
             preload: [vars: ^from(v in Brando.Content.Var, order_by: [asc: v.sequence])]
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

    case Brando.Datasource.list_results(Module.concat([ds_module]), query, vars, language && to_string(language)) do
      {:ok, identifiers} when is_list(identifiers) -> identifiers
      _ -> []
    end
  rescue
    _ -> []
  end

  def selection_options(_module, _language), do: []

  defp language({:new, ref}, proposal) do
    case Enum.find(proposal.operations, &match?(%CreateEntry{ref: ^ref}, &1)) do
      %{fields: fields} -> fields["language"]
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

  defp new_uid(uid, tree) do
    taken? =
      BlockTree.fetch(tree, uid) != nil or
        Repo.one(from(b in Content.Block, where: b.uid == ^uid, select: true, limit: 1)) == true

    if taken?,
      do: {:error, problem(:duplicate_uid, dgettext("content_proposals", "Another block already uses this uid."))},
      else: :ok
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

    for key <- Map.keys(fields), key in @protected_fields or key in blocks do
      problem(
        :protected_field,
        dgettext("content_proposals", "%{field} cannot be changed by a proposal.", field: key)
      )
    end
  end

  defp draft_dependencies(values, proposal) do
    for {_, {:new, ref}} <- values, Map.has_key?(proposal.targets, {:new, to_string(ref)}) do
      problem(
        :draft_dependency,
        dgettext(
          "content_proposals",
          "This links to a new entry, which is created as a draft. Its page will not be public until it is published."
        )
      )
    end
  end

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
  The module set a block field's form declares (`blocks :blocks, module_set: …`).
  It limits the root modules the editor's picker offers; `nil` allows all.
  """
  @spec module_set(module(), String.t()) :: String.t() | nil
  def module_set(schema, field) do
    with %{blocks: inputs} <- schema.__form__(),
         %{opts: opts} <- Enum.find(inputs, &(to_string(&1.name) == field)) do
      opts[:module_set]
    else
      _ -> nil
    end
  end

  defp module_id(module), do: {Map.get(module, :library_origin) || :local, module.id}

  defp values(values, vars, actor) do
    Enum.flat_map(values, fn {key, value} ->
      value_problems(Enum.find(vars || [], &(&1.key == key)), key, value, actor)
    end)
  end

  defp value_problems(nil, key, _value, _actor),
    do: [problem(:unknown_var, dgettext("content_proposals", "The module has no variable %{key}.", key: key))]

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

  # Text, markdown and HTML refs must pass the same safety check as the
  # editor's rich text; header refs hold plain text, svg refs one safe
  # `<svg>`, and map refs an https embed address.
  defp text(name, text, module) do
    case Enum.find(module.refs || [], &(&1.name == name)) do
      %{data: %{type: type}} when is_binary(text) ->
        case text_problem(type, text, name) do
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

  # A link to an entry that was not resolved is reported as such.
  defp text_problem(type, text, name) when type in ["text", "markdown", "html"] do
    unless EntryLinks.unresolved?(text) or Brando.RichText.safe_html?(text),
      do: dgettext("content_proposals", "%{name} contains unsafe rich text.", name: name)
  end

  defp text_problem("header", text, name) do
    if String.contains?(text, ["<", ">"]), do: dgettext("content_proposals", "%{name} takes plain text.", name: name)
  end

  defp text_problem("svg", text, name) do
    unless Brando.RichText.safe_svg?(text),
      do: dgettext("content_proposals", "%{name} takes one safe <svg> element.", name: name)
  end

  defp text_problem("map", text, name) do
    unless String.starts_with?(text, "https://"),
      do: dgettext("content_proposals", "%{name} takes an https embed address.", name: name)
  end

  defp text_problem(_type, _text, _name), do: :unknown

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
  whichever of picture, video and gallery it makes available.
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
    existing = for {{schema, _} = target, entry} <- proposal.targets, schema != :new, do: {target, entry}
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
      creates: Enum.count(proposal.operations, &match?(%CreateEntry{}, &1)),
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
         {block, _parent, _index} <- BlockTree.find_saved(Map.get(entry, :"entry_#{field}", []), uid) do
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

  defp materialize!(proposal, entries, user) do
    Map.new(proposal.targets, fn {target, _} ->
      {target, target |> base_changeset(proposal, entries, user) |> put_blocks(target, proposal, entries, user)}
    end)
  end

  defp base_changeset({:new, ref} = target, proposal, _entries, user) do
    schema = Map.fetch!(proposal.targets, target)
    %CreateEntry{fields: fields} = Enum.find(proposal.operations, &match?(%CreateEntry{ref: ^ref}, &1))
    schema.changeset(struct(schema), schema |> EntryFields.params(fields) |> Map.put("status", "draft"), user, nil, [])
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

  defp put_media(ref, {:file, id}, _module, _user), do: Changeset.put_change(ref, :file_id, id)

  # A media slot is retyped from its module definition's template, as the
  # editor's media block does when an editor picks a picture, a video or a
  # gallery.
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
  defp put_text(ref, text) do
    %{type: type, data: inner} = block = Changeset.get_field(ref, :data)

    key =
      case type do
        "svg" -> :code
        "map" -> :embed_url
        _ -> :text
      end

    Changeset.put_change(ref, :data, %{block | data: Map.put(inner, key, text)})
  end

  defp template(%{data: %{type: "media", data: data}}, "picture"),
    do: %Brando.Villain.Blocks.PictureBlock{
      type: "picture",
      data: data.template_picture || %Brando.Villain.Blocks.PictureBlock.Data{}
    }

  defp template(%{data: %{type: "media", data: data}}, "video"),
    do: %Brando.Villain.Blocks.VideoBlock{
      type: "video",
      data: data.template_video || %Brando.Villain.Blocks.VideoBlock.Data{}
    }

  defp template(%{data: %{type: "media", data: data}}, "gallery"),
    do: %Brando.Villain.Blocks.GalleryBlock{
      type: "gallery",
      data: data.template_gallery || %Brando.Villain.Blocks.GalleryBlock.Data{}
    }

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

  defp put_value(var, :link, {:entry, schema, id}, _user) do
    {:ok, identifier} = Content.get_identifier(schema, %{id: id})
    Changeset.change(var, link_type: :identifier, identifier_id: identifier.id)
  end

  defp put_value(var, :link, url, _user) when is_binary(url), do: Changeset.change(var, link_type: :url, value: url)
  defp put_value(var, _type, value, _user), do: Changeset.put_change(var, :value, value)

  ## Store, approve and apply

  @ttl :timer.hours(24)

  @doc """
  Prepare `operations` and store them as a proposal version for review.

  Options:

    * `:conversation_id` — the conversation the proposal belongs to
    * `:supersedes` — the id of the proposal this one refines. It is marked
      `superseded`, its approval lapses, and this proposal takes the next version.
    * `:summary` — a short description for review

  Validation problems do not fail; they are stored and block approval.
  """
  @spec propose([struct()], term(), keyword()) :: {:ok, Proposal.t()} | {:error, String.t()}
  def propose(operations, actor, opts \\ []) do
    with {:ok, proposal} <- prepare(operations, actor) do
      Error.protect(fn -> store!(proposal, actor, opts) end)
    end
  end

  defp store!(proposal, actor, opts) do
    {:ok, record} =
      Repo.transaction(fn ->
        previous = supersede!(opts[:supersedes], actor)
        Repo.insert!(new_record(proposal, previous, opts))
      end)

    with_record(proposal, record)
  end

  defp supersede!(nil, _actor), do: nil

  defp supersede!(id, actor) do
    previous = record!(id, actor, lock: true)

    if previous.status not in ~w(pending approved),
      do: Error.fail!(dgettext("content_proposals", "Only a proposal under review can be refined."))

    previous |> Changeset.change(status: "superseded") |> Repo.update!()
  end

  defp new_record(proposal, previous, opts) do
    %Record{
      id: proposal.id,
      conversation_id: if(previous, do: previous.conversation_id, else: opts[:conversation_id]),
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
  Record the actor's approval of exactly `version` of proposal `id`.

  Only a pending, unexpired proposal without problems can be approved, and
  only while its entries and modules are unchanged. The approval is what
  `apply/3` requires; a model cannot approve on the user's behalf.
  """
  @spec approve(Ecto.UUID.t(), integer(), term()) :: {:ok, Proposal.t()} | {:error, String.t()}
  def approve(id, version, actor) do
    Error.protect(fn ->
      {:ok, record} = Repo.transaction(fn -> approve!(id, version, actor) end)
      rebuild!(record, actor)
    end)
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
      case for {op, index} <- Enum.with_index(operations), index not in indices, do: op do
        [] -> {:error, dgettext("content_proposals", "Nothing would be left. Discard the proposal instead.")}
        rest -> propose(rest, actor, supersedes: id, summary: record.summary)
      end
    end
  end

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
    Error.protect(fn ->
      record = record!(id, actor)
      user = user!(actor)
      receipt = receipt(id, actor)

      cond do
        record.status == "undone" ->
          Error.fail!(dgettext("content_proposals", "This proposal has already been undone."))

        record.status != "applied" or is_nil(receipt) ->
          Error.fail!(dgettext("content_proposals", "Only an applied proposal can be undone."))

        true ->
          :ok
      end

      saved =
        for {key, %{"schema" => name, "id" => entry_id, "fingerprint" => fingerprint}} <- receipt.after do
          {:ok, schema} = Codec.schema(name)
          {key, schema, entry_id, fingerprint}
        end

      changed =
        for {_key, schema, entry_id, fingerprint} <- saved,
            entry = load!({schema, entry_id}, actor),
            Transfer.entry_fingerprint(entry) != fingerprint,
            do: Catalog.describe(entry).title

      if changed != [],
        do:
          Error.fail!(
            dgettext("content_proposals", "%{entries} changed after the proposal was applied. Undo would overwrite that.",
              entries: Enum.join(changed, ", ")
            )
          )

      without_revision =
        for {key, _schema, _id, _} <- saved,
            !String.starts_with?(key, "new:"),
            is_nil(receipt.before[key]["revision"]),
            do: key

      if without_revision != [],
        do: Error.fail!(dgettext("content_proposals", "An entry has no earlier revision to go back to."))

      {:ok, receipt} =
        Repo.transaction(fn ->
          Enum.each(saved, fn {key, schema, entry_id, _} ->
            if String.starts_with?(key, "new:"),
              do: delete_entry!(schema, entry_id, user),
              else: restore!(schema, entry_id, receipt.before[key]["revision"], user)
          end)

          record |> Changeset.change(status: "undone") |> Repo.update!()

          receipt
          |> Changeset.change(mappings: Map.put(receipt.mappings, "undone_at", DateTime.to_iso8601(DateTime.utc_now())))
          |> Repo.update!()
        end)

      receipt
    end)
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
  review it read-only. The viewer must be able to read its entries; only the
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

      rebuild!(record, viewer, :read)
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
  Apply the approved `version` of proposal `id` atomically and return its receipt.

  Entries are locked and compared with the proposal's fingerprints; a changed
  entry or module aborts without writing. Applying an applied proposal again
  returns its receipt.
  """
  @spec apply(Ecto.UUID.t(), integer(), term()) :: {:ok, Receipt.t()} | {:error, String.t()}
  def apply(id, version, actor, opts \\ []) do
    result =
      Error.protect(fn ->
        record = record!(id, actor)

        if record.status == "applied" do
          {receipt(id, actor), []}
        else
          reviewable!(record, version, "approved")
          record |> rebuild!(actor) |> apply!(actor, opts)
        end
      end)

    with {:ok, {receipt, saved}} <- result do
      Enum.each(saved, &after_apply(&1, actor))
      {:ok, receipt}
    end
  end

  # What follows an editor's save, once the proposal is committed: the
  # traits' after-save work and the sync of synchronized translations, then
  # notifications and broadcasts.
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
    {:ok, operations} = Codec.decode_all(record.operations)
    creates = for %CreateEntry{} = op <- operations, into: %{}, do: {{:new, op.ref}, op.schema}

    entries =
      for op <- operations,
          target <- op_targets(op),
          match?({schema, id} when schema != :new and is_integer(id), target),
          uniq: true,
          into: %{},
          do: {target, load!(target, actor, action: action)}

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

    effects = decode_effects(record.effects, Map.keys(proposal.targets))
    with_record(%{proposal | effects: effects}, record)
  end

  defp with_record(proposal, record) do
    %{
      proposal
      | version: record.version,
        status: record.status,
        conversation_id: record.conversation_id,
        summary: record.summary,
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
      target: problem["target"]
    }
  end

  defp encode_effects(effects) do
    Map.new(effects, fn
      {:live, targets} -> {"live", Enum.map(targets, &Proposal.key/1)}
      {key, value} -> {to_string(key), value}
    end)
  end

  defp decode_effects(effects, targets) do
    live = Enum.filter(targets, &(Proposal.key(&1) in (effects["live"] || [])))

    %{
      creates: effects["creates"],
      updates: effects["updates"],
      inserted_blocks: effects["inserted_blocks"],
      updated_blocks: effects["updated_blocks"],
      moved_blocks: effects["moved_blocks"] || 0,
      deletions: effects["deletions"],
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
      proposal.fingerprints
      |> Map.keys()
      |> Enum.sort_by(fn {schema, id} -> {to_string(schema), id} end)
      |> Enum.map(&load!(&1, actor, lock: true))

    Transfer.lock_records!(%{fields: Enum.map(locked, &%{entry: &1}), bindings: %{}})
    entries = current!(proposal, actor)
    # The revision each entry is at now: undo restores it.
    revisions = Map.new(entries, fn {target, entry} -> {target, revision_before(target, entry, user)} end)

    # Create first: later stages resolve `{:new, ref}` to the saved id.
    # Otherwise entries are saved in the order the operations name them.
    saved =
      proposal
      |> materialize!(entries, user)
      |> Enum.map(fn {target, cs} ->
        if Proposal.key(target) in publish,
          do: {target, Changeset.put_change(cs, :status, :published)},
          else: {target, cs}
      end)
      |> Enum.sort_by(fn {target, _} -> {!match?({:new, _}, target), first_mention(proposal, target)} end)
      |> Enum.map(fn {target, cs} = pair ->
        {^target, entry} = save!(pair, user)
        {target, entry, cs}
      end)

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
          "published" => publish,
          "effects" => encode_effects(proposal.effects)
        }
      })

    record |> Changeset.change(status: "applied") |> Repo.update!()
    {receipt, saved}
  end

  # Publishing is the reviewer's choice at apply, per entry: new entries are
  # drafts otherwise, and drafts stay drafts. It takes the publish permission.
  defp publish_targets!(proposal, actor, keys) do
    keys = Enum.map(keys, &to_string/1)

    for key <- keys do
      target = Enum.find(Map.keys(proposal.targets), &(Proposal.key(&1) == key))
      schema = target && proposal_schema(proposal, target)

      cond do
        is_nil(schema) or not schema.has_trait(Brando.Trait.Status) ->
          Error.fail!(dgettext("content_proposals", "Only entries in this proposal that have a status can be published."))

        Boundary.authorize(actor, :publish, schema) != :ok ->
          Error.fail!(dgettext("content_proposals", "You do not have permission to publish this entry."))

        true ->
          key
      end
    end
  end

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
      %CreateEntry{ref: ref} -> {:new, ref} == target
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

    unless Enum.all?(entries, fn {target, entry} -> Transfer.entry_fingerprint(entry) == proposal.fingerprints[target] end),
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
