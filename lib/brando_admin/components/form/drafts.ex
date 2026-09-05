defmodule BrandoAdmin.Components.Form.Drafts do
  @moduledoc "Recovery capture coordination. It never uses the save/preview accumulators or ships focus."
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [connected?: 1, push_event: 3, send_update: 2, send_update_after: 3]
  alias Brando.Drafts
  alias Brando.Drafts.Modules
  alias Brando.Drafts.Params
  alias Brando.Drafts.Restore

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

      payload = %{
        "main" => main_params(socket, socket.assigns.form.source),
        "blocks" => blocks,
        "transformers" => transformers,
        "modules" => Modules.manifest(blocks)
      }

      state = %{
        initialized?: true,
        id: Ecto.UUID.generate(),
        identity: identity,
        generation: 0,
        persisted: 0,
        baseline: Drafts.checksum(payload),
        checksum: Drafts.checksum(payload),
        base_fingerprint: Drafts.fingerprint(entry),
        modules: payload["modules"],
        capture: nil,
        candidates: Drafts.list(identity),
        open?: false,
        selected: nil,
        error: nil,
        compatible?: false,
        comparison: [],
        issues: [],
        save_generation: nil,
        status: :ready,
        saved_at: nil
      }

      assign(socket, :draft, state)
    else
      assign(socket, :draft, nil)
    end
  rescue
    error ->
      require Logger
      Logger.error("Recovery copies unavailable: #{inspect(error.__struct__)}")
      assign(socket, :draft, nil)
  end

  def dirty(%{assigns: %{draft: %{initialized?: true} = draft}} = socket) do
    socket
    |> assign(:draft, %{draft | generation: draft.generation + 1, status: :saving})
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
      main: main_params(socket, cs),
      parts: %{},
      expected: expected
    }

    socket = assign(socket, :draft, %{draft | capture: capture, status: :saving})

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
    socket |> assign(:draft, %{draft | capture: capture}) |> finish()
  end

  def part(socket, _, _, _, _), do: socket

  def timeout(%{assigns: %{draft: %{capture: %{id: id}}}} = socket, id), do: fail_capture(socket)
  def timeout(socket, _), do: socket

  defp finish(%{assigns: %{draft: %{capture: capture} = draft}} = socket) do
    if Enum.all?(capture.expected, &Map.has_key?(capture.parts, &1)) do
      blocks = Map.new(capture.parts, fn {{kind, field}, value} -> {{kind, field}, value} end) |> parts(:block)
      manifest = Modules.manifest(blocks)
      modules = Map.merge(manifest, Map.take(draft.modules, Map.keys(manifest)))

      payload = %{
        "main" => capture.main,
        "blocks" => blocks,
        "transformers" => parts(capture.parts, :transformer),
        "modules" => modules
      }

      checksum = Drafts.checksum(payload)
      generation = max(capture.generation, draft.persisted + if(checksum != draft.checksum, do: 1, else: 0))

      result =
        cond do
          checksum == draft.checksum ->
            {:ok, nil}

          checksum == draft.baseline ->
            Drafts.resolve(draft.identity, draft.id, generation)

          true ->
            Drafts.write(
              draft.identity,
              draft.id,
              generation,
              payload,
              draft.base_fingerprint,
              Brando.Blueprint.Snapshot.get_current_version(socket.assigns.schema)
            )
        end

      case result do
        {:ok, _} ->
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
          |> assign(:draft, state)
          |> push_event("b:draft-saved", %{
            id: socket.assigns.id,
            generation: capture.client_generation,
            draft_id: state.id
          })

        _ ->
          fail_capture(socket)
      end
    else
      socket
    end
  rescue
    _ -> fail_capture(socket)
  end

  defp parts(parts, kind), do: Map.new(for {{^kind, field}, value} <- parts, do: {field, value})

  defp fail_capture(%{assigns: %{draft: draft}} = socket) when is_map(draft) do
    assign(socket, :draft, %{draft | capture: nil, status: :error})
  end

  defp fail_capture(socket), do: socket

  def before_save(%{assigns: %{draft: %{save_generation: nil} = draft}} = socket),
    do: assign(socket, :draft, %{draft | save_generation: draft.generation})

  def before_save(socket), do: socket

  def save_result(%{assigns: %{draft: draft, processing: false}} = socket) when is_map(draft),
    do: assign(socket, :draft, %{draft | save_generation: nil})

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
         assign(socket, :draft, %{
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
    Drafts.resolve(draft.identity, draft.id, generation)
    # Resolved originals remain available for the retention window, but never
    # re-enter the normal recovery list after a successful explicit save.
    if draft.selected && draft.issues == [] && draft.generation <= generation,
      do: Drafts.resolve(draft.identity, draft.selected.id, draft.selected.generation)

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

    checksum = Drafts.checksum(payload)

    socket
    |> assign(:draft, %{
      draft
      | id: Ecto.UUID.generate(),
        identity: identity,
        capture: nil,
        save_generation: nil,
        candidates: Drafts.list(identity),
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

        saved = socket.assigns.schema.changeset(entry, %{}, socket.assigns.current_user)
        main = main_params(socket, saved)

        recovered =
          case selected.payload["main"] do
            values when is_map(values) -> values
            _ -> %{}
          end

        comparison =
          recovered
          |> Enum.filter(fn {key, value} -> !is_map(value) && !is_list(value) && value != main[key] end)
          |> Enum.sort()
          |> Enum.map(fn {key, value} -> %{field: Phoenix.Naming.humanize(key), saved: main[key], recovered: value} end)

        assign(socket, :draft, %{
          socket.assigns.draft
          | selected: selected,
            open?: true,
            error: nil,
            issues: [],
            compatible?: false,
            comparison: comparison
        })
    end
  end

  def dismiss(socket) do
    draft = socket.assigns.draft
    Enum.each(draft.candidates, &Drafts.dismiss(draft.identity, &1.id))
    assign(socket, :draft, %{draft | candidates: Drafts.list(draft.identity), open?: false, error: nil})
  end

  def discard(socket, id) do
    draft = socket.assigns.draft
    Drafts.discard(draft.identity, id)

    assign(socket, :draft, %{
      draft
      | candidates: Drafts.list(draft.identity),
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
      result = Restore.prepare(original, entry, socket.assigns.schema, socket.assigns.current_user, opts)
      state = %{draft | selected: original, open?: true, candidates: Drafts.list(draft.identity), compatible?: false}

      case result do
        {:ok, cs, issues} ->
          {:ok,
           socket
           |> assign(:entry, entry)
           |> assign(:draft, %{
             state
             | id: Ecto.UUID.generate(),
               modules: original.payload["modules"] || %{},
               capture: nil,
               base_fingerprint: Drafts.fingerprint(entry),
               error: nil,
               issues: issues
           }), cs}

        {:review, reason, issues} ->
          message =
            if reason == :entry_changed,
              do: "The saved entry changed after this recovery copy was made. Review it before restoring.",
              else:
                "Some blocks use modules that have changed. You can recover compatible content and keep the original copy."

          {:error, assign(socket, :draft, %{state | error: message, issues: issues, compatible?: true})}

        {:error, message} ->
          {:error, assign(socket, :draft, %{state | error: message})}
      end
    else
      _ -> {:error, assign(socket, :draft, %{draft | error: "This recovery copy is no longer available.", open?: true})}
    end
  rescue
    _ ->
      {:error,
       assign(socket, :draft, %{
         socket.assigns.draft
         | error: "This recovery copy could not be applied. You can continue with the saved entry.",
           open?: true
       })}
  end

  def main_params(socket, changeset) do
    schema = socket.assigns.schema
    names = Enum.flat_map(socket.assigns.form_blueprint.tabs, &field_names/1)
    allowed = Enum.map(schema.__schema__(:fields), &to_string/1) ++ names
    blocks = Enum.map(socket.assigns.form_blueprint.blocks, &"entry_#{&1.name}")
    transformers = Enum.map(socket.assigns.form_blueprint.transformers, fn {name, _, _} -> to_string(name) end)

    changeset
    |> Params.snapshot()
    |> Map.take(allowed)
    |> Map.drop(blocks ++ transformers ++ ["id", "creator_id", "deleted_at"])
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
