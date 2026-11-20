defmodule BrandoAdmin.Components.Form.TranslationFill do
  @moduledoc """
  Translate with AI on a synchronized translation's work list
  (`BrandoAdmin.Components.Form.Translation`): the open *translate* and
  *review* texts, or one of them, are translated in the background
  (`Brando.AI.WorkTranslation`) and the replies fill the form as unsaved
  changes. Nothing is saved and no work item is resolved: the editor checks
  the texts and saves, and the save resolves them as it does typed text.

  The units come from `Brando.Translations.Work.translation_units/2`, read
  from the pending version the form holds. A run remembers what each text
  was when it started (`baseline`): a field here, a block's text in its
  BlockField (`"translation_fill_start"`). A text that changed by the time
  the reply comes, by this editor or another, keeps its text and is marked
  `:kept`. A reply for another entry, or for a pending version the form no
  longer holds or that has since been replaced, is dropped.

  Fields are written by the Form through its local-change path
  (`put_written_form/2`), and block texts by each BlockField as field ops
  through the edit session (`"translation_fill"`), so other editors, field
  sync, presence and recovery see them as typed text.

  State is the Form's `:translation_fill` assign, nil before a run:

    * `run` — the run's id; replies from an earlier one are ignored
    * `status` — `:running`, `:done`, `:failed` or `:dropped`
    * `entry_id`, `version_id` — what the run was made for
    * `keys` — the units sent
    * `progress` — `{batches_done, batches}`
    * `marks` — by key: `:filled`, `:kept`, `{:skipped, code}`, kept
      across runs of the same version
    * `baseline` — field texts at the start, by key
  """
  use Gettext, backend: Brando.Gettext

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [start_async: 3, send_update: 2, send_update: 3, connected?: 1]

  alias Brando.AI.WorkTranslation
  alias Brando.Translations
  alias Brando.Translations.Work
  alias BrandoAdmin.Components.Form.BlockField
  alias BrandoAdmin.Components.Form.Translation
  alias Ecto.Changeset

  @doc "Whether the form offers Translate with AI: a synchronized translation, AI configured."
  def available?(%{translation: %{ai?: true}}), do: true
  def available?(_assigns), do: false

  @doc "Whether a run is in progress."
  def running?(%{status: :running}), do: true
  def running?(_fill), do: false

  @doc """
  Starts a run over `keys` (`:all` for every open text). Returns the socket,
  with the reason in a toast when nothing was started.
  """
  def start(socket, keys) do
    assigns = socket.assigns

    with true <- available?(assigns) and assigns.tab_editing? and connected?(socket),
         false <- running?(assigns[:translation_fill]),
         version_id when is_integer(version_id) <- Translation.version_id(assigns),
         {:ok, work} <- Work.translation_units(assigns.schema, assigns.entry.id),
         true <- work.version_id == version_id || {:error, :stale},
         [_ | _] = units <- units(work.units, keys) do
      run(socket, work, units)
    else
      {:error, :stale} -> toast(socket, gettext("The source changed. Save the translation, then translate with AI."))
      [] -> toast(socket, gettext("Nothing here needs translating."))
      _ -> socket
    end
  end

  defp units(units, keys) do
    Enum.filter(units, &(WorkTranslation.translatable?(&1) and (keys == :all or &1.key in keys)))
  end

  defp run(socket, work, units) do
    %{id: form_id, entry: entry, translation: state} = socket.assigns
    run = System.unique_integer([:positive])
    targets = targets(state)
    previous = socket.assigns[:translation_fill]
    keys = Enum.map(units, & &1.key)

    baseline =
      for key <- keys, form_target?(targets[key]), into: %{} do
        {key, field_value(socket.assigns.form.source, targets[key])}
      end

    for {field, block_targets} <- block_targets(keys, targets) do
      send_update(BlockField,
        id: "#{form_id}-blocks-#{field}",
        event: "translation_fill_start",
        run: run,
        targets: block_targets
      )
    end

    lv = self()

    progress = fn step ->
      send_update(lv, BrandoAdmin.Components.Form, id: form_id, action: :translation_fill_progress, run: run, step: step)
    end

    source_language = work.source_language
    language = work.language

    socket
    |> assign(:translation_fill, %{
      run: run,
      status: :running,
      entry_id: entry.id,
      version_id: work.version_id,
      keys: keys,
      progress: {0, 1},
      marks: marks_for(previous, work.version_id) |> Map.drop(keys),
      baseline: baseline,
      counts: nil
    })
    |> start_async(:translation_fill, fn ->
      {run, WorkTranslation.translate(units, source_language, language, progress: progress)}
    end)
  end

  defp marks_for(%{version_id: version_id, marks: marks}, version_id), do: marks
  defp marks_for(_previous, _version_id), do: %{}

  # Where each open item's text is in the form, by key
  defp targets(state), do: Map.new(state.items, &{&1.path, &1.target})

  # Block texts by block field: `{key, uid, path below the block}`
  defp block_targets(keys, targets) do
    keys
    |> Enum.flat_map(fn key ->
      case {targets[key], String.split(key, "/", parts: 2)} do
        {{:block, uid, _module, rest}, ["entry_" <> field, _]} -> [{field, {key, uid, rest}}]
        _ -> []
      end
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  @doc "A batch is done: `{batches_done, batches}`."
  def progress(socket, run, step) do
    case socket.assigns[:translation_fill] do
      %{run: ^run, status: :running} = fill -> assign(socket, :translation_fill, %{fill | progress: step})
      _ -> socket
    end
  end

  @doc """
  The reply of run `run`. Returns `{socket, writes}`: the field texts to
  write, `{key, target, text}`, which the Form puts in through its
  local-change path and reports back with `fields_written/3`. Block texts
  are sent to their BlockFields here.
  """
  def finish(socket, run, result) do
    case socket.assigns[:translation_fill] do
      %{run: ^run} = fill -> finish_run(socket, fill, result)
      _ -> {socket, []}
    end
  end

  defp finish_run(socket, fill, result) do
    cond do
      not current?(socket, fill) ->
        {assign(socket, :translation_fill, %{fill | status: :dropped}), []}

      match?({:ok, {:ok, _}}, result) ->
        {:ok, {:ok, %{texts: texts, problems: problems}}} = result
        fill(socket, fill, texts, problems)

      true ->
        {assign(socket, :translation_fill, %{fill | status: :failed}), []}
    end
  end

  # The reply is for the entry and the pending version the form holds, and
  # the version is still the translation's pending one.
  defp current?(socket, fill) do
    %{schema: schema, entry: entry} = socket.assigns

    entry.id == fill.entry_id and Translation.version_id(socket.assigns) == fill.version_id and
      match?(%{id: id} when id == fill.version_id, Translations.get_pending_version(schema, entry.id))
  end

  defp fill(socket, fill, texts, problems) do
    targets = targets(socket.assigns.translation)
    skipped = Map.new(problems, fn {key, [problem | _]} -> {key, {:skipped, problem.code}} end)
    {field_texts, block_texts} = Enum.split_with(texts, fn {key, _text} -> form_target?(targets[key]) end)

    for {field, entries} <- block_targets(Enum.map(block_texts, &elem(&1, 0)), targets) do
      texts = for {key, uid, rest} <- entries, do: {key, uid, rest, Map.fetch!(texts, key)}

      send_update(BlockField,
        id: "#{socket.assigns.id}-blocks-#{field}",
        event: "translation_fill",
        run: fill.run,
        texts: texts
      )
    end

    # A text the editor no longer has where it was (a block removed since)
    lost = for {key, _text} <- block_texts, not Map.has_key?(targets, key), into: %{}, do: {key, :kept}

    {writes, kept} =
      Enum.split_with(field_texts, fn {key, _text} ->
        field_value(socket.assigns.form.source, targets[key]) == Map.get(fill.baseline, key)
      end)

    marks =
      fill.marks
      |> Map.merge(skipped)
      |> Map.merge(lost)
      |> Map.merge(Map.new(kept, fn {key, _} -> {key, :kept} end))

    socket = assign(socket, :translation_fill, %{fill | status: :done, marks: marks})
    {socket, Enum.map(writes, fn {key, text} -> {key, targets[key], text} end)}
  end

  @doc "Marks what the Form wrote (`:filled`) and could not write (`:kept`)."
  def fields_written(socket, written, failed), do: mark(socket, nil, written, failed)

  @doc "A BlockField's answer to `\"translation_fill\"`."
  def blocks_filled(socket, run, filled, kept), do: mark(socket, run, filled, kept)

  defp mark(socket, run, filled, kept) do
    case socket.assigns[:translation_fill] do
      %{run: current} = fill when run in [nil, current] ->
        marks =
          fill.marks
          |> Map.merge(Map.new(filled, &{&1, :filled}))
          |> Map.merge(Map.new(kept, &{&1, :kept}))

        assign(socket, :translation_fill, %{fill | marks: marks})

      _ ->
        socket
    end
  end

  @doc "Clears the marks of a pending version the form no longer holds."
  def refresh(socket) do
    case {socket.assigns[:translation_fill], Translation.version_id(socket.assigns)} do
      {%{version_id: version_id}, version_id} -> socket
      {%{status: :running} = fill, _} -> assign(socket, :translation_fill, %{fill | marks: %{}})
      {nil, _} -> socket
      _ -> assign(socket, :translation_fill, nil)
    end
  end

  @doc "Counts of a finished run's marks, for its status line."
  def counts(%{keys: keys, marks: marks}) do
    run = Map.take(marks, keys)

    %{
      filled: Enum.count(run, &match?({_, :filled}, &1)),
      not_filled: Enum.count(run, &(not match?({_, :filled}, &1)))
    }
  end

  ## Fields

  # A text the Form writes: a field, or a field of a subform's row
  defp form_target?({:field, _}), do: true
  defp form_target?({:row, _subform, _key, _field}), do: true
  defp form_target?(_target), do: false

  @doc "A field's or a subform row's text as `changeset` has it, `:error` for none."
  def field_value(changeset, {:field, field}) do
    case field_name(changeset, field) do
      {:ok, name} -> Changeset.get_field(changeset, name)
      :error -> :error
    end
  end

  def field_value(changeset, {:row, subform, key, field}) do
    with {:ok, _kind, _assoc, rows} <- rows(changeset, subform),
         {_index, row} <- find_row(rows, key),
         {:ok, name} <- field_name(row, field) do
      Changeset.get_field(row, name)
    else
      _ -> :error
    end
  end

  def field_value(_changeset, _target), do: :error

  @doc "Puts `text` into a field or a subform row's field of `changeset`: `{:ok, changeset}` or `:error`."
  def put_field(changeset, {:field, field}, text) do
    case field_name(changeset, field) do
      {:ok, name} -> {:ok, Changeset.put_change(changeset, name, text)}
      :error -> :error
    end
  end

  def put_field(changeset, {:row, subform, key, field}, text) do
    with {:ok, kind, assoc, rows} <- rows(changeset, subform),
         {index, row} <- find_row(rows, key),
         {:ok, name} <- field_name(row, field) do
      rows = List.replace_at(rows, index, Changeset.put_change(row, name, text))

      case kind do
        :assoc -> {:ok, Changeset.put_assoc(changeset, assoc, rows)}
        :embed -> {:ok, Changeset.put_embed(changeset, assoc, rows)}
      end
    else
      _ -> :error
    end
  end

  def put_field(_changeset, _target, _text), do: :error

  defp field_name(%Changeset{data: %schema{}}, field) do
    with {:ok, name} <- existing_atom(field),
         true <- name in schema.__schema__(:fields) do
      {:ok, name}
    else
      _ -> :error
    end
  end

  # A has_many's or embeds_many's rows, as changesets
  defp rows(%Changeset{data: %schema{}} = changeset, subform) do
    with {:ok, name} <- existing_atom(subform),
         kind when kind != nil <- relation_kind(schema, name),
         rows when is_list(rows) <- Changeset.get_assoc(changeset, name, :changeset) do
      {:ok, kind, name, rows}
    else
      _ -> :error
    end
  end

  defp relation_kind(schema, name) do
    cond do
      match?(%{cardinality: :many}, schema.__schema__(:association, name)) -> :assoc
      match?(%{cardinality: :many}, schema.__schema__(:embed, name)) -> :embed
      true -> nil
    end
  end

  # A row by the key `Brando.Translations.Sync` names it with: its uid, or a
  # variable's key
  defp find_row(rows, key) do
    rows
    |> Enum.with_index()
    |> Enum.find_value(fn {%Changeset{data: %schema{}} = row, index} ->
      field = if :uid in schema.__schema__(:fields), do: :uid, else: :key
      if to_string(Changeset.get_field(row, field)) == key, do: {index, row}
    end)
  end

  defp existing_atom(name) do
    {:ok, String.to_existing_atom(name)}
  rescue
    ArgumentError -> :error
  end

  defp toast(socket, message) do
    send(self(), {:toast, message})
    socket
  end
end
