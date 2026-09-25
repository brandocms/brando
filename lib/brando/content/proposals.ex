defmodule Brando.Content.Proposals do
  use Gettext, backend: Brando.Gettext

  @moduledoc """
  Reviewed content changes across several saved entries.

  A proposal is a list of semantic operations — `CreateEntry`, `SetFields`,
  `InsertBlock`, `SetBlockMedia`, `SetBlockValues` and `SetBlockText` — that `prepare/2`
  resolves against the actor's content, validates and freezes. Nothing is
  written until `apply/2`:

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
  alias Brando.Content.Proposals.Codec
  alias Brando.Content.Proposals.CreateEntry
  alias Brando.Content.Proposals.InsertBlock
  alias Brando.Content.Proposals.Proposal
  alias Brando.Content.Proposals.Receipt
  alias Brando.Content.Proposals.Record
  alias Brando.Content.Proposals.SetBlockMedia
  alias Brando.Content.Proposals.SetBlockText
  alias Brando.Content.Proposals.SetBlockValues
  alias Brando.Content.Proposals.SetFields
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
  @media_kinds %{image: "picture", video: "video"}

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
    operations = Enum.map(operations, &freeze/1)
    creates = for %CreateEntry{} = op <- operations, into: %{}, do: {{:new, op.ref}, op.schema}

    entries =
      operations
      |> Enum.map(&Map.get(&1, :target))
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

    problems =
      operations
      |> Enum.with_index()
      |> Enum.flat_map(fn {op, index} -> Enum.map(check(op, proposal, actor), &Map.put(&1, :operation, index)) end)

    problems = if problems == [], do: check_changesets(proposal, entries, user), else: problems
    %{proposal | problems: problems, effects: effects(proposal)}
  end

  defp freeze(%CreateEntry{} = op), do: %{op | ref: to_string(op.ref), fields: stringify(op.fields)}
  defp freeze(%SetFields{} = op), do: %{op | target: target(op.target), fields: stringify(op.fields)}

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
        module: module_reference(op.module),
        uid: op.uid || Utils.generate_uid(),
        values: stringify(op.values),
        texts: stringify(op.texts),
        media: stringify(op.media),
        ref_uids: Map.new(refs, &{&1.name, op.ref_uids[&1.name] || Utils.generate_uid()})
    }
  end

  defp freeze(%SetBlockMedia{} = op), do: %{op | target: target(op.target), field: to_string(op.field)}

  defp freeze(%SetBlockText{} = op), do: %{op | target: target(op.target), field: to_string(op.field)}

  defp freeze(%SetBlockValues{} = op),
    do: %{op | target: target(op.target), field: to_string(op.field), values: stringify(op.values)}

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
        protected_fields(op.fields, op.schema) ++ draft_dependencies(op.fields, proposal)
    end
  end

  defp check(%SetFields{target: {:new, _}}, _, _),
    do: [problem(:unknown_target, dgettext("content_proposals", "Set the fields of a new entry when creating it."))]

  defp check(%SetFields{} = op, proposal, _actor) do
    {schema, _} = op.target
    protected_fields(op.fields, schema) ++ draft_dependencies(op.fields, proposal)
  end

  defp check(%InsertBlock{} = op, proposal, actor) do
    with {:ok, schema} <- target_schema(op.target, proposal),
         :ok <- block_field(schema, op.field),
         {:ok, module} <- allowed_module(op.module, schema, op.field),
         :ok <- placement(op, proposal) do
      values(op.values, module.vars) ++
        Enum.flat_map(op.texts, fn {name, text} -> text(name, text, module) end) ++
        Enum.flat_map(op.media, fn {name, asset} -> media(name, asset, module, actor) end) ++
        draft_dependencies(op.values, proposal)
    else
      {:error, problem} -> [problem]
    end
  end

  defp check(%{block_uid: uid} = op, proposal, actor) do
    with {:ok, schema} <- target_schema(op.target, proposal),
         :ok <- block_field(schema, op.field),
         {:ok, module} <- block_module(op, uid, proposal) do
      case op do
        %SetBlockMedia{ref: name, asset: asset} -> media(to_string(name), asset, module, actor)
        %SetBlockValues{values: values} -> values(values, module.vars) ++ draft_dependencies(values, proposal)
        %SetBlockText{ref: name, text: text} -> text(to_string(name), text, module)
      end
    else
      {:error, problem} -> [problem]
    end
  end

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

      module.parent_id || module.multi || module_id(module) not in allowed_module_ids(schema, field, module) ->
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

  defp placement(%InsertBlock{placement: :append}, _proposal), do: :ok

  defp placement(%InsertBlock{placement: {side, uid}} = op, proposal) when side in [:before, :after] do
    if uid in root_uids(op.target, op.field, proposal, op.uid),
      do: :ok,
      else:
        {:error,
         problem(:unknown_placement, dgettext("content_proposals", "The block to insert next to is not in this field."))}
  end

  defp placement(_op, _proposal),
    do: {:error, problem(:unknown_placement, dgettext("content_proposals", "Unknown placement."))}

  # Root block UIDs an insertion may be placed next to: the saved root blocks
  # of the field, and blocks the proposal inserts before the block `until`.
  defp root_uids(target, field, proposal, until) do
    saved =
      case Map.get(proposal.targets, target) do
        %{} = entry -> Enum.map(Map.fetch!(entry, :"entry_#{field}"), & &1.block.uid)
        _ -> []
      end

    inserted =
      proposal.operations
      |> Enum.take_while(&(!match?(%InsertBlock{uid: ^until}, &1)))
      |> Enum.flat_map(fn
        %InsertBlock{target: ^target, field: ^field, uid: uid} -> [uid]
        _ -> []
      end)

    saved ++ inserted
  end

  defp block_module(op, uid, proposal) do
    inserted = Enum.find(proposal.operations, &match?(%InsertBlock{uid: ^uid}, &1))
    saved = saved_block(op.target, op.field, uid, proposal)

    cond do
      inserted && inserted.target == op.target && inserted.field == op.field ->
        {:ok, fetch_module(inserted.module)}

      saved && saved.type == :module ->
        {:ok, Content.fetch_module(saved.module_id, saved.module_origin || :local)}

      true ->
        {:error,
         problem(:unknown_block, dgettext("content_proposals", "This block is not a root module block of the field."))}
    end
  end

  defp saved_block(target, field, uid, proposal) do
    case Map.get(proposal.targets, target) do
      %{} = entry -> entry |> Map.fetch!(:"entry_#{field}") |> Enum.find_value(&(&1.block.uid == uid && &1.block))
      _ -> nil
    end
  end

  defp values(values, vars) do
    Enum.flat_map(values, fn {key, value} -> value_problems(Enum.find(vars || [], &(&1.key == key)), key, value) end)
  end

  defp value_problems(nil, key, _value),
    do: [problem(:unknown_var, dgettext("content_proposals", "The module has no variable %{key}.", key: key))]

  defp value_problems(var, key, value), do: if(settable?(var, value), do: [], else: [unsupported(var, key, value)])

  defp settable?(%{type: :boolean}, value), do: is_boolean(value)
  defp settable?(%{type: type}, value) when type in @text_vars, do: is_binary(value)
  defp settable?(%{type: :select, options: options}, value), do: Enum.any?(options || [], &(&1.value == value))
  defp settable?(_, _), do: false

  defp unsupported(%{type: :select}, key, value) when is_binary(value),
    do:
      problem(
        :unsupported_value,
        dgettext("content_proposals", "%{key} has no option %{value}.", key: key, value: value)
      )

  defp unsupported(_var, key, _value),
    do: problem(:unsupported_value, dgettext("content_proposals", "%{key} cannot be set to this value.", key: key))

  # Text refs hold rich text that must pass the same safety check as the
  # editor; header refs hold plain text.
  defp text(name, text, module) do
    case Enum.find(module.refs || [], &(&1.name == name)) do
      %{data: %{type: "text"}} when is_binary(text) ->
        if Brando.RichText.safe_html?(text),
          do: [],
          else: [problem(:unsafe_text, dgettext("content_proposals", "%{name} contains unsafe rich text.", name: name))]

      %{data: %{type: "header"}} when is_binary(text) ->
        if String.contains?(text, ["<", ">"]),
          do: [problem(:unsafe_text, dgettext("content_proposals", "%{name} takes plain text.", name: name))],
          else: []

      _ ->
        [problem(:unknown_ref, dgettext("content_proposals", "The module has no text slot %{name}.", name: name))]
    end
  end

  defp media(name, {kind, id}, module, actor) when kind in [:image, :video] do
    case Enum.find(module.refs || [], &(&1.name == name)) do
      nil ->
        [problem(:unknown_ref, dgettext("content_proposals", "The module has no media slot %{name}.", name: name))]

      ref ->
        cond do
          kind not in accepts(ref) ->
            [
              problem(
                :wrong_media_type,
                dgettext("content_proposals", "%{name} does not accept this media type.", name: name)
              )
            ]

          match?({:error, _}, Error.protect(fn -> Dependencies.load!(to_string(kind), id, actor) end)) ->
            [problem(:missing_asset, dgettext("content_proposals", "This media is no longer in the library."))]

          true ->
            []
        end
    end
  end

  defp media(_name, _asset, _module, _actor),
    do: [problem(:wrong_media_type, dgettext("content_proposals", "Only images and videos can be placed."))]

  @doc """
  The media kinds a module ref accepts: a picture ref takes an image, a video
  ref a video, and a media slot whichever of the two it makes available.
  """
  @spec accepts(Brando.Content.Ref.t()) :: [:image | :video]
  def accepts(%{data: %{type: "picture"}}), do: [:image]
  def accepts(%{data: %{type: "video"}}), do: [:video]

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
    inserted = for %InsertBlock{uid: uid} <- proposal.operations, do: uid

    %{
      creates: Enum.count(proposal.operations, &match?(%CreateEntry{}, &1)),
      updates: length(existing),
      inserted_blocks: length(inserted),
      updated_blocks:
        proposal.operations
        |> Enum.flat_map(fn
          %{block_uid: uid} = op -> if uid in inserted, do: [], else: [{op.target, uid}]
          _ -> []
        end)
        |> Enum.uniq()
        |> length(),
      deletions: 0,
      live: for({target, %{status: :published}} <- existing, do: target)
    }
  end

  ## Materialize

  @doc """
  Build every target's changeset in memory from the frozen operations.

  Reloads the entries and refuses when one changed since `prepare/2`.
  Returns `%{target => changeset}`; nothing is saved.
  """
  @spec materialize(Proposal.t(), term()) :: {:ok, %{Proposal.target() => Changeset.t()}} | {:error, String.t()}
  def materialize(%Proposal{} = proposal, actor) do
    Error.protect(fn ->
      authorize_proposal!(proposal, actor)
      materialize!(proposal, current!(proposal, actor), user!(actor))
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
    schema.changeset(struct(schema), Map.put(fields, "status", "draft"), user, nil, [])
  end

  defp base_changeset({schema, _} = target, proposal, entries, user) do
    fields =
      for %SetFields{target: ^target, fields: fields} <- proposal.operations,
          reduce: %{},
          do: (acc -> Map.merge(acc, fields))

    schema.changeset(Map.fetch!(entries, target), fields, user, nil, [])
  end

  defp put_blocks(changeset, target, proposal, entries, user) do
    schema = changeset.data.__struct__

    ops =
      proposal.operations
      |> Enum.filter(&(Map.get(&1, :target) == target && Map.has_key?(&1, :field)))
      |> Enum.group_by(& &1.field)

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

  defp block_op(%InsertBlock{} = op, joins, join_schema, user) do
    module = fetch_module(op.module)

    block =
      op.module
      |> Content.SharedLibrary.reference()
      |> Blocks.build_module_block(user.id, nil, join_schema, :module)
      |> Changeset.put_change(:uid, op.uid)
      |> update_refs(fn ref ->
        name = Changeset.get_field(ref, :name)
        ref = Changeset.put_change(ref, :uid, Map.fetch!(op.ref_uids, name))
        ref = if text = op.texts[name], do: put_text(ref, text), else: ref
        if asset = op.media[name], do: put_media(ref, asset, module), else: ref
      end)
      |> put_values(op.values)

    join =
      join_schema
      |> struct()
      |> Changeset.change()
      |> Changeset.put_assoc(:block, block)
      |> Map.put(:action, :insert)

    index =
      case op.placement do
        :append -> length(joins)
        {:before, uid} -> Enum.find_index(joins, &(elem(&1, 0) == uid))
        {:after, uid} -> Enum.find_index(joins, &(elem(&1, 0) == uid)) + 1
      end

    List.insert_at(joins, index, {op.uid, join})
  end

  defp block_op(%SetBlockMedia{} = op, joins, _join_schema, _user) do
    name = to_string(op.ref)

    update_block(joins, op.block_uid, fn block ->
      module =
        Content.fetch_module(Changeset.get_field(block, :module_id), Changeset.get_field(block, :module_origin) || :local)

      update_refs(block, &if(Changeset.get_field(&1, :name) == name, do: put_media(&1, op.asset, module), else: &1))
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

  defp block_op(%SetBlockValues{} = op, joins, _join_schema, _user),
    do: update_block(joins, op.block_uid, &put_values(&1, op.values))

  defp update_block(joins, uid, fun) do
    Enum.map(joins, fn
      {^uid, join} -> {uid, Changeset.put_assoc(join, :block, fun.(Changeset.get_assoc(join, :block)))}
      other -> other
    end)
  end

  defp update_refs(block, fun), do: Changeset.put_assoc(block, :refs, Enum.map(Changeset.get_assoc(block, :refs), fun))

  # A media slot is retyped from its module definition's template, as the
  # editor's media block does when an editor picks a picture or a video.
  defp put_media(ref, {kind, id}, module) do
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
      end

    Changeset.put_change(ref, :"#{kind}_id", id)
  end

  defp put_text(ref, text) do
    %{data: inner} = block = Changeset.get_field(ref, :data)
    Changeset.put_change(ref, :data, %{block | data: %{inner | text: text}})
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

  defp put_values(block, values) when values == %{}, do: block

  defp put_values(block, values) do
    vars =
      block
      |> Changeset.get_assoc(:vars)
      |> Enum.map(fn var ->
        case {Map.fetch(values, Changeset.get_field(var, :key)), Changeset.get_field(var, :type)} do
          {{:ok, value}, :boolean} -> Changeset.put_change(var, :value_boolean, value)
          {{:ok, value}, _} -> Changeset.put_change(var, :value, value)
          {:error, _} -> var
        end
      end)

    Changeset.put_assoc(block, :vars, vars)
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
  def apply(id, version, actor) do
    result =
      Error.protect(fn ->
        record = record!(id, actor)

        if record.status == "applied" do
          {receipt(id, actor), []}
        else
          reviewable!(record, version, "approved")
          record |> rebuild!(actor) |> apply!(actor)
        end
      end)

    with {:ok, {receipt, saved}} <- result do
      Enum.each(saved, &announce(&1, actor))
      {:ok, receipt}
    end
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

  defp rebuild!(record, actor) do
    {:ok, operations} = Codec.decode_all(record.operations)
    creates = for %CreateEntry{} = op <- operations, into: %{}, do: {{:new, op.ref}, op.schema}

    entries =
      for op <- operations,
          target = Map.get(op, :target),
          match?({schema, id} when schema != :new and is_integer(id), target),
          uniq: true,
          into: %{},
          do: {target, load!(target, actor)}

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
      deletions: effects["deletions"],
      live: live
    }
  end

  defp apply!(proposal, actor) do
    authorize_proposal!(proposal, actor)

    if proposal.problems != [],
      do: Error.fail!(dgettext("content_proposals", "Resolve every blocking problem before applying."))

    case receipt(proposal.id, actor) do
      %Receipt{} = receipt -> {receipt, []}
      nil -> apply_new!(proposal, actor)
    end
  end

  defp apply_new!(proposal, actor) do
    {:ok, result} =
      Repo.transaction(fn ->
        Ecto.Adapters.SQL.query!(Repo.repo(), "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
          "brando-content-proposal:" <> Transfer.scope()
        ])

        case receipt(proposal.id, actor) do
          %Receipt{} = receipt -> {receipt, []}
          nil -> apply_locked!(proposal, actor, user!(actor))
        end
      end)

    result
  end

  defp apply_locked!(proposal, actor, user) do
    record = record!(proposal.id, actor, lock: true)

    unless record.status == "approved" and record.version == proposal.version,
      do: Error.fail!(dgettext("content_proposals", "Approve this version of the proposal before applying it."))

    locked =
      proposal.fingerprints
      |> Map.keys()
      |> Enum.sort_by(fn {schema, id} -> {to_string(schema), id} end)
      |> Enum.map(&load!(&1, actor, lock: true))

    Transfer.lock_records!(%{fields: Enum.map(locked, &%{entry: &1}), bindings: %{}})
    entries = current!(proposal, actor)

    # Create first: later stages resolve `{:new, ref}` to the saved id.
    # Otherwise entries are saved in the order the operations name them.
    saved =
      proposal
      |> materialize!(entries, user)
      |> Enum.sort_by(fn {target, _} -> {!match?({:new, _}, target), first_mention(proposal, target)} end)
      |> Enum.map(&save!(&1, user))

    receipt =
      Repo.insert!(%Receipt{
        id: proposal.id,
        version: proposal.version,
        scope: proposal.scope,
        actor_id: user.id,
        before: Map.new(entries, &snapshot(&1, proposal)),
        after: Map.new(saved, &saved_fingerprint(&1, actor)),
        mappings: %{
          "created" => for({{:new, ref}, entry} <- saved, into: %{}, do: {ref, entry.id}),
          "effects" => encode_effects(proposal.effects)
        }
      })

    record |> Changeset.change(status: "applied") |> Repo.update!()
    {receipt, saved}
  end

  defp snapshot({target, entry}, proposal),
    do: {Proposal.key(target), %{"fingerprint" => proposal.fingerprints[target], "entry" => Params.snapshot(entry)}}

  defp saved_fingerprint({target, entry}, actor) do
    entry = load!({entry.__struct__, entry.id}, actor)

    {Proposal.key(target),
     %{"schema" => to_string(entry.__struct__), "id" => entry.id, "fingerprint" => Transfer.entry_fingerprint(entry)}}
  end

  defp first_mention(proposal, target) do
    Enum.find_index(proposal.operations, fn
      %CreateEntry{ref: ref} -> {:new, ref} == target
      op -> Map.get(op, :target) == target
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
  def current!(proposal, actor) do
    entries = Map.new(proposal.fingerprints, fn {target, _} -> {target, load!(target, actor)} end)

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

  defp load!({schema, id}, actor, opts \\ []), do: Catalog.load!(schema, id, actor, :update, opts)

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
