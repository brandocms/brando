defmodule BrandoAdmin.Components.Form.Drafts do
  @moduledoc "Recovery capture coordination. It never uses the save/preview accumulators or ships focus."
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [connected?: 1, push_event: 3, send_update: 2, send_update_after: 3]
  alias Brando.Drafts
  alias Brando.Drafts.Content
  alias Brando.Drafts.Modules
  alias Brando.Drafts.Params
  alias Brando.Drafts.Restore
  alias BrandoAdmin.Components.Form.DraftPreview
  alias BrandoAdmin.Components.Form.DraftRecoveryComponent

  def init(%{assigns: %{draft: %{initialized?: true}}} = socket), do: socket

  def init(socket) do
    if connected?(socket) do
      %{schema: schema, entry: entry, current_user: user, form_blueprint: blueprint} = socket.assigns
      identity = Drafts.identity(schema, entry.id, user.id, blueprint.name)

      blocks =
        Map.new(blueprint.blocks, fn field ->
          {to_string(field.name), Params.snapshot(Map.get(entry, :"entry_#{field.name}") || [])}
        end)

      transformers =
        Map.new(blueprint.transformers, fn {name, _, _} ->
          {to_string(name), Params.snapshot(Map.get(entry, name) || [])}
        end)

      # The baseline is the saved entry. A heavy entry starts recovery once
      # its blocks have loaded, and by then the form may hold edits already
      # (recovered after a reconnect, sent by other editors): those are
      # changes to keep a copy of, not part of the baseline.
      payload = %{
        "main" => main_params(socket, saved_changeset(socket)),
        "blocks" => blocks,
        "transformers" => transformers,
        "modules" => Modules.manifest(blocks)
      }

      baseline = Content.checksum(payload)
      current = Content.checksum(%{payload | "main" => main_params(socket, socket.assigns.form.source)})

      state = %{
        initialized?: true,
        id: Ecto.UUID.generate(),
        identity: identity,
        generation: 0,
        persisted: 0,
        baseline: baseline,
        checksum: baseline,
        base_fingerprint: Drafts.fingerprint(entry),
        modules: payload["modules"],
        capture: nil,
        candidates: candidates(socket, identity, baseline),
        open?: false,
        selected: nil,
        error: nil,
        compatible?: false,
        preview: [],
        issues: [],
        save_generation: nil,
        status: :ready,
        saved_at: nil
      }

      socket = put_draft(socket, state)
      # The browser captures what it shows; it is asked to now, rather than at
      # the next keystroke.
      if current != baseline, do: dirty(socket), else: socket
    else
      put_draft(socket, nil)
    end
  rescue
    error ->
      require Logger
      Logger.error("Recovery copies unavailable: #{inspect(error.__struct__)}")
      put_draft(socket, nil)
  end

  # The form an untouched entry opens with (`Form.assign_form/1`), from the
  # entry as it was read (`:opened_entry`): the form's data can have taken in
  # edits by then (an asset delivery bakes the changes). A new entry has no
  # saved state: its baseline is the form with its default values.
  defp saved_changeset(%{assigns: %{entry: %{id: nil}, form: form}}), do: form.source

  defp saved_changeset(%{assigns: %{schema: schema, current_user: user} = assigns}),
    do: schema.changeset(assigns[:opened_entry] || assigns.form.source.data, %{}, user)

  @doc """
  Keeps the entry recovery is baselined against (`:opened_entry`, read by
  `init/1`) while recovery has not started: the entry as read, then as each
  save leaves it. Once recovery has started the baseline lives in its state,
  and nothing more is kept.
  """
  def keep_baseline(%{assigns: %{draft: %{initialized?: true}}} = socket, _entry),
    do: assign(socket, :opened_entry, nil)

  def keep_baseline(socket, entry), do: assign(socket, :opened_entry, entry)

  @doc """
  Sets the form's recovery state, and hands it to the status component.

  The form's own template doesn't read `@draft`: the state changes on every
  autosave, and a change in the form's diff makes LiveView patch the whole
  form (tens of thousands of elements on a case with blocks). The status
  renders in `DraftRecoveryComponent`, which only gets the state on its first
  render (`:draft_seed`) and from here after that.
  """
  def put_draft(socket, draft) do
    socket =
      socket
      |> assign(:draft, draft)
      |> assign(:draft_enabled?, not is_nil(draft))

    socket =
      if is_nil(socket.assigns[:draft_seed]) and not is_nil(draft),
        do: assign(socket, :draft_seed, draft),
        else: socket

    for id <- [DraftRecoveryComponent.id(socket.assigns.id), DraftRecoveryComponent.status_id(socket.assigns.id)] do
      send_update(DraftRecoveryComponent, id: id, state: draft)
    end

    socket
  end

  def dirty(%{assigns: %{draft: %{initialized?: true} = draft}} = socket) do
    socket
    |> put_draft(%{draft | generation: draft.generation + 1, status: :saving})
    |> push_event("b:draft-dirty", %{id: socket.assigns.id})
  end

  def dirty(socket), do: socket

  def capture(%{assigns: %{draft: nil}} = socket, _), do: socket
  def capture(%{assigns: %{processing: true}} = socket, _), do: socket
  def capture(%{assigns: %{blocks_ready?: false}} = socket, _), do: socket
  def capture(%{assigns: %{draft: %{capture: capture}}} = socket, _) when not is_nil(capture), do: socket

  def capture(socket, params) do
    draft = socket.assigns.draft
    id = Ecto.UUID.generate()
    blueprint = socket.assigns.form_blueprint

    expected =
      Enum.map(blueprint.blocks, &{:block, to_string(&1.name)}) ++
        Enum.map(blueprint.transformers, fn {name, _, _} -> {:transformer, to_string(name)} end)

    raw = Plug.Conn.Query.decode(params["main"] || "")[socket.assigns.singular]

    forms =
      Map.new(params["blocks"] || %{}, fn {uid, encoded} ->
        decoded = Plug.Conn.Query.decode(encoded)
        {uid, decoded["entry_block"] || decoded["child_block"] || %{}}
      end)

    cs =
      if raw,
        do: socket.assigns.schema.changeset(socket.assigns.entry, raw, socket.assigns.current_user),
        else: socket.assigns.form.source

    capture = %{
      id: id,
      generation: draft.generation,
      client_generation: params["generation"],
      request_id: params["request_id"],
      main: main_params(socket, cs),
      parts: %{},
      expected: expected
    }

    socket = put_draft(socket, %{draft | capture: capture, status: :saving})

    for field <- blueprint.blocks do
      send_update(BrandoAdmin.Components.Form.BlockField,
        id: "#{socket.assigns.id}-blocks-#{field.name}",
        event: "capture_draft",
        capture_id: id,
        reply_to: socket.assigns.myself,
        forms: forms
      )
    end

    for {name, _, _} <- blueprint.transformers do
      send_update(BrandoAdmin.Components.Form.Transformer,
        id: "#{socket.assigns.form.id}-transformer-#{name}",
        event: "capture_draft",
        capture_id: id,
        reply_to: socket.assigns.myself
      )
    end

    send_update_after(socket.assigns.myself, [event: "draft_timeout", capture_id: id], 10_000)
    finish(socket)
  rescue
    _ -> fail_capture(socket)
  end

  def part(%{assigns: %{draft: %{capture: %{id: id} = capture} = draft}} = socket, id, kind, field, data) do
    capture = %{capture | parts: Map.put(capture.parts, {kind, to_string(field)}, data)}
    socket |> put_draft(%{draft | capture: capture}) |> finish()
  end

  def part(socket, _, _, _, _), do: socket

  def timeout(%{assigns: %{draft: %{capture: %{id: id}}}} = socket, id), do: fail_capture(socket)
  def timeout(socket, _), do: socket

  defp finish(%{assigns: %{draft: %{capture: capture} = draft}} = socket) do
    if Enum.all?(capture.expected, &Map.has_key?(capture.parts, &1)),
      do: save_capture(socket, draft, capture),
      else: socket
  rescue
    _ -> fail_capture(socket)
  end

  defp save_capture(socket, draft, capture) do
    blocks = Map.new(capture.parts, fn {{kind, field}, value} -> {{kind, field}, value} end) |> parts(:block)
    manifest = Modules.manifest(blocks)
    modules = Map.merge(manifest, Map.take(draft.modules, Map.keys(manifest)))

    payload = %{
      "main" => capture.main,
      "blocks" => blocks,
      "transformers" => parts(capture.parts, :transformer),
      "modules" => modules
    }

    # a revision's working copy, unsaved: restored, it is one again
    payload =
      case socket.assigns[:working_copy] do
        nil -> payload
        revision -> Map.put(payload, "working_copy", %{"revision" => revision})
      end

    checksum = Content.checksum(payload)
    generation = max(capture.generation, draft.persisted + if(checksum != draft.checksum, do: 1, else: 0))

    case persist_capture(socket, draft, checksum, generation, payload) do
      {draft, {:ok, _}} -> mark_capture_saved(socket, draft, capture, modules, checksum, generation)
      _ -> fail_capture(socket)
    end
  end

  defp persist_capture(socket, draft, checksum, generation, payload) do
    cond do
      checksum == draft.checksum ->
        {draft, {:ok, nil}}

      checksum == draft.baseline ->
        {draft, Drafts.resolve(draft.identity, draft.id, generation)}

      true ->
        write_capture(socket, draft, generation, payload)
    end
  end

  defp mark_capture_saved(socket, draft, capture, modules, checksum, generation) do
    state = %{
      draft
      | capture: nil,
        modules: modules,
        generation: max(draft.generation, generation),
        persisted: generation,
        checksum: checksum,
        status: :saved,
        saved_at: DateTime.utc_now()
    }

    state =
      if checksum == draft.baseline && checksum != draft.checksum,
        do: %{state | id: Ecto.UUID.generate()},
        else: state

    socket
    |> put_draft(state)
    |> push_event("b:draft-saved", %{
      id: socket.assigns.id,
      generation: capture.client_generation,
      request_id: capture.request_id,
      draft_id: state.id
    })
  end

  defp write_capture(socket, draft, generation, payload) do
    version = Brando.Blueprint.Snapshot.get_current_version(socket.assigns.schema)

    case Drafts.write(draft.identity, draft.id, generation, payload, draft.base_fingerprint, version) do
      {:error, :closed} ->
        # Another tab can discard/resolve an equivalent copy. Keep that original
        # closed, but store this tab's subsequent edit under a fresh session ID.
        next = %{draft | id: Ecto.UUID.generate()}
        {next, Drafts.write(next.identity, next.id, generation, payload, next.base_fingerprint, version)}

      result ->
        {draft, result}
    end
  end

  defp candidates(socket, identity, baseline, opts \\ []) do
    version = Brando.Blueprint.Snapshot.get_current_version(socket.assigns.schema)
    {:ok, _} = Drafts.resolve_unchanged(identity, baseline, version, opts)
    Drafts.candidates(identity, baseline: baseline, schema_version: version)
  end

  defp parts(parts, kind), do: Map.new(for {{^kind, field}, value} <- parts, do: {field, value})

  defp fail_capture(%{assigns: %{draft: draft}} = socket) when is_map(draft) do
    put_draft(socket, %{draft | capture: nil, status: :error})
  end

  defp fail_capture(socket), do: socket

  def before_save(%{assigns: %{draft: %{save_generation: nil} = draft}} = socket),
    do: put_draft(socket, %{draft | save_generation: draft.generation})

  def before_save(socket), do: socket

  def save_result(%{assigns: %{draft: draft, processing: false}} = socket) when is_map(draft),
    do: put_draft(socket, %{draft | save_generation: nil})

  def save_result(socket), do: socket

  def check_save(%{assigns: %{draft: %{selected: selected} = draft, all_blocks_received?: true}} = socket)
      when not is_nil(selected) do
    blocks =
      Map.new(socket.assigns.block_changesets, fn {field, rows} -> {to_string(field), Params.snapshot(rows || [])} end)

    {_, issues} = Modules.check(blocks, Map.merge(Modules.manifest(blocks), draft.modules))

    if issues == [],
      do: :ok,
      else:
        {:error,
         put_draft(socket, %{
           draft
           | open?: true,
             issues: issues,
             error:
               "A module changed while you were editing. Review the recovery copy or open the saved version before saving.",
             save_generation: nil
         })}
  end

  def check_save(_), do: :ok

  def saved(%{assigns: %{draft: draft}} = socket, entry) when is_map(draft) do
    generation = draft.save_generation || draft.generation
    # Settle copies of the PREVIOUS saved content before switching baselines.
    # Merely hiding them would turn them into apparent unsaved work after save.
    {:ok, _} =
      Drafts.resolve_unchanged(
        draft.identity,
        draft.baseline,
        Brando.Blueprint.Snapshot.get_current_version(socket.assigns.schema),
        compact: true
      )

    Drafts.resolve(draft.identity, draft.id, generation, compact: true)
    # Only a complete, successfully saved restore releases the original payload.
    # Failed/partial restores and newer generations retain their recovery content.
    if draft.selected && draft.issues == [] && draft.generation <= generation,
      do: Drafts.resolve_equivalent(draft.identity, draft.selected, compact: true)

    Drafts.rebind_entry(draft.identity, draft.id, entry.id)
    if draft.selected, do: Drafts.rebind_entry(draft.identity, draft.selected.id, entry.id)
    identity = %{draft.identity | entry_id: entry.id}
    cs = socket.assigns.schema.changeset(entry, %{}, socket.assigns.current_user)

    blocks =
      Map.new(socket.assigns.form_blueprint.blocks, fn field ->
        {to_string(field.name), Params.snapshot(Map.get(entry, :"entry_#{field.name}") || [])}
      end)

    transformers =
      Map.new(socket.assigns.form_blueprint.transformers, fn {name, _, _} ->
        {to_string(name), Params.snapshot(Map.get(entry, name) || [])}
      end)

    payload = %{
      "main" => main_params(socket, cs),
      "blocks" => blocks,
      "transformers" => transformers,
      "modules" => Modules.manifest(blocks)
    }

    checksum = Content.checksum(payload)

    socket
    |> put_draft(%{
      draft
      | id: Ecto.UUID.generate(),
        identity: identity,
        capture: nil,
        save_generation: nil,
        candidates: candidates(socket, identity, checksum, compact: true),
        selected: nil,
        issues: [],
        error: nil,
        open?: false,
        status: :ready,
        base_fingerprint: Drafts.fingerprint(entry),
        modules: payload["modules"],
        baseline: checksum,
        checksum: checksum,
        saved_at: nil
    })
    |> push_event("b:draft-reset", %{id: socket.assigns.id, clean: draft.generation <= generation})
  rescue
    _ -> fail_capture(socket)
  end

  def saved(socket, _), do: push_event(socket, "b:draft-reset", %{id: socket.assigns.id, clean: true})

  def review(socket, id) do
    case Drafts.get(socket.assigns.draft.identity, id) do
      nil ->
        socket

      selected ->
        entry =
          case fresh_entry(socket) do
            {:ok, entry} -> entry
            _ -> socket.assigns.entry
          end

        # Compare with the freshly loaded saved entry, never the working editor.
        saved_payload =
          saved_payload(socket.assigns.schema, socket.assigns.form_blueprint, entry, socket.assigns.current_user)

        put_draft(socket, %{
          socket.assigns.draft
          | selected: selected,
            open?: true,
            error: nil,
            issues: [],
            compatible?: false,
            preview:
              DraftPreview.comparisons(saved_payload, selected.payload,
                schema: socket.assigns.schema,
                blueprint: socket.assigns.form_blueprint
              )
        })
    end
  end

  def dismiss(socket) do
    draft = socket.assigns.draft
    Enum.each(draft.candidates, &Drafts.dismiss(draft.identity, &1.id))

    put_draft(socket, %{
      draft
      | candidates: candidates(socket, draft.identity, draft.baseline),
        open?: false,
        error: nil
    })
  end

  def discard(socket, id) do
    draft = socket.assigns.draft
    Drafts.discard(draft.identity, id)

    put_draft(socket, %{
      draft
      | candidates: candidates(socket, draft.identity, draft.baseline),
        selected: nil,
        open?: false,
        error: nil,
        issues: []
    })
  end

  def prepare_restore(socket, id, opts) do
    draft = socket.assigns.draft

    with {:ok, original} <- Drafts.begin_restore(draft.identity, id),
         {:ok, entry} <- fresh_entry(socket) do
      # Restoring settles every copy that was on offer, just like "Continue
      # without restoring" does. `begin_restore` only dismisses the chosen copy,
      # so without this the notice returns for the copies passed over — and for
      # equivalent twins of the restored one, since the deduplicated candidate
      # list may not represent the copy that was actually restored. The copies
      # stay listed in the panel; only the notice goes quiet.
      Enum.each(draft.candidates, &Drafts.dismiss(draft.identity, &1.id))

      result = Restore.prepare(original, entry, socket.assigns.schema, socket.assigns.current_user, opts)

      state = %{
        draft
        | selected: original,
          open?: true,
          candidates: candidates(socket, draft.identity, draft.baseline),
          compatible?: false
      }

      case result do
        {:ok, cs, issues} ->
          {:ok,
           socket
           |> assign(:entry, entry)
           |> put_draft(%{
             state
             | id: Ecto.UUID.generate(),
               modules: original.payload["modules"] || %{},
               capture: nil,
               base_fingerprint: Drafts.fingerprint(entry),
               error: nil,
               issues: issues
           }), cs}

        {:review, reason, issues} ->
          {:error, put_draft(socket, %{state | error: review_message(reason), issues: issues, compatible?: true})}

        {:error, message} ->
          {:error, put_draft(socket, %{state | error: message})}
      end
    else
      _ -> {:error, put_draft(socket, %{draft | error: "This recovery copy is no longer available.", open?: true})}
    end
  rescue
    _ ->
      {:error,
       put_draft(socket, %{
         socket.assigns.draft
         | error: "This recovery copy could not be applied. You can continue with the saved entry.",
           open?: true
       })}
  end

  defp review_message(reason) do
    if reason == :entry_changed,
      do: "The saved entry changed after this recovery copy was made. Review it before restoring.",
      else: "Some blocks use modules that have changed. You can recover compatible content and keep the original copy."
  end

  def main_params(socket, changeset), do: main_params(socket.assigns.schema, socket.assigns.form_blueprint, changeset)

  def main_params(schema, blueprint, changeset) do
    names = Enum.flat_map(blueprint.tabs, &field_names/1)
    allowed = Enum.map(schema.__schema__(:fields), &to_string/1) ++ names
    blocks = Enum.map(blueprint.blocks, &"entry_#{&1.name}")
    transformers = Enum.map(blueprint.transformers, fn {name, _, _} -> to_string(name) end)

    changeset
    |> Params.snapshot()
    |> Map.take(allowed)
    |> Map.drop(blocks ++ transformers ++ ["id", "creator_id", "deleted_at"])
  end

  @doc """
  A saved entry in the shape of a recovery payload (`"main"`, `"blocks"`,
  `"transformers"`), so `DraftPreview.comparisons/3` can compare it with a
  recovery copy or with another saved state of the entry, such as a revision.
  """
  def saved_payload(schema, blueprint, entry, user) do
    saved = schema.changeset(entry, %{}, user)

    %{
      "main" => main_params(schema, blueprint, saved),
      "blocks" =>
        Map.new(blueprint.blocks, fn field ->
          {to_string(field.name), Params.snapshot(Map.get(entry, :"entry_#{field.name}") || [])}
        end),
      "transformers" =>
        Map.new(blueprint.transformers, fn {name, _, _} ->
          {to_string(name), Params.snapshot(Map.get(entry, name) || [])}
        end)
    }
  end

  defp fresh_entry(%{assigns: %{entry: %{id: nil} = entry}}), do: {:ok, entry}

  defp fresh_entry(socket) do
    %{schema: schema, entry: entry, form_blueprint: blueprint} = socket.assigns
    query = Brando.Blueprint.Forms.resolve_query(blueprint.query, entry.id)

    query =
      if is_nil(blueprint.query), do: Map.put(query, :preload, Brando.Blueprint.Preloads.for_schema(schema)), else: query

    apply(schema.__modules__().context, :"get_#{schema.__naming__().singular}", [Map.put(query, :with_deleted, true)])
  end

  defp field_names(%{fields: fields}), do: Enum.flat_map(fields, &field_names/1)
  defp field_names(%{name: name}) when not is_nil(name), do: [to_string(name)]
  defp field_names(_), do: []
end
