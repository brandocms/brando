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
    * `reading` — while the texts are read before the run starts: the
      units, the texts read so far and the BlockFields still to answer;
      nil once the run has started
  """
  use Gettext, backend: Brando.Gettext

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [start_async: 3, send_update: 2, send_update: 3, connected?: 1]

  alias Brando.AI.WorkTranslation
  alias Brando.Translations
  alias Brando.Translations.Work
  alias BrandoAdmin.Components.Form.BlockField
  alias BrandoAdmin.Components.Form.LockedFields
  alias BrandoAdmin.Components.Form.Translation
  alias BrandoAdmin.Components.Form.Visibility
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

  The run first reads the texts as the form has them (block texts from their
  BlockFields, `"translation_fill_start"`, answered by `block_texts_read/4`)
  and only then sends them (`begin/1`). Translate with AI for every text
  leaves out what the editor has worked on: items ticked Reviewed, and texts
  that are no longer the pending version's. An item's own action translates
  it in any case. A review sends the translation as the form has it.
  """
  def start(socket, keys) do
    assigns = socket.assigns

    with true <- available?(assigns) and assigns.tab_editing? and connected?(socket),
         true <- may_write?(assigns),
         false <- running?(assigns[:translation_fill]),
         version_id when is_integer(version_id) <- Translation.version_id(assigns),
         {:ok, work} <- Work.translation_units(assigns.schema, assigns.entry.id),
         true <- work.version_id == version_id || {:error, :stale},
         [_ | _] = units <- units(work.units, keys, targets(assigns.translation), fillable(assigns)) do
      read(socket, work, units, keys)
    else
      {:error, :stale} -> toast(socket, gettext("The source changed. Save the translation, then translate with AI."))
      [] -> toast(socket, gettext("Nothing here needs translating."))
      _ -> socket
    end
  end

  # The editor may change the entry: the check a clicked run (a `:write`
  # event, `EventGuard`) and one the form starts itself (`?translate=ai`)
  # share. A legacy `:user` account may not.
  defp may_write?(%{current_user: user, entry: entry}), do: Brando.Authorization.Boundary.may_update?(user, entry)

  defp units(units, keys, targets, fillable) do
    Enum.filter(units, fn unit ->
      WorkTranslation.translatable?(unit) and fillable.(unit.key, targets[unit.key]) and
        (keys == :all or unit.key in keys)
    end)
  end

  @doc """
  The paths of the open items this editor's form can fill
  (`fillable/1`): the items with an AI action.
  """
  def actionable(%{translation: %{items: items}} = assigns) do
    if available?(assigns) do
      fillable = fillable(assigns)
      for %{path: path, target: target} <- items, fillable.(path, target), into: MapSet.new(), do: path
    else
      MapSet.new()
    end
  end

  def actionable(_assigns), do: MapSet.new()

  @doc """
  Whether this editor's form can fill the text an item points at, as a
  function of the item's key and target; what a run sends and what has an
  AI action. Not:

    * a gallery's per-image texts, which are translated in the block
    * an address (a link's `url`), which is not sent to the model and stays
      the editor's
    * a field or a subform's row locked for this editor (`LockedFields`:
      read-only, or in a fieldset only superusers may change)
    * a field or a row's field the form has no input for, or hides
      (`hidden:`, `show_if:`): a text put there would not reach the browser
      and would be lost at its next `validate`
    * a block text in a block field the form has none of
  """
  def fillable(%{schema: schema, form_blueprint: blueprint, current_user: user, form: form}) do
    locked = schema |> LockedFields.keys(blueprint, user) |> Enum.map(&to_string/1)
    inputs = for input <- top_inputs(blueprint), into: %{}, do: {to_string(input.name), input}
    block_fields = Enum.map(blueprint.blocks || [], &to_string(&1.name))

    fn
      _key, {:block, _uid, _module, ["refs", _name, "gallery" | _]} ->
        false

      key, {:block, _uid, _module, path} when is_list(path) ->
        not address?(path) and block_field(key) in block_fields

      _key, {:field, field} ->
        field not in locked and shown?(inputs[field], form)

      _key, {:row, subform, _row, field} = target ->
        field != "url" and subform not in locked and row_shown?(inputs[subform], form.source, target)

      _key, _target ->
        false
    end
  end

  defp address?(["url"]), do: true
  defp address?([_ | rest]), do: address?(rest)
  defp address?([]), do: false

  # The top-level inputs and subforms of the form's fieldsets
  defp top_inputs(%{tabs: tabs}) when is_list(tabs) do
    for %{fields: fieldsets} <- tabs, %{fields: fields} <- fieldsets, %{name: name} = input <- fields, name != nil,
        do: input
  end

  defp top_inputs(_blueprint), do: []

  defp shown?(%Brando.Blueprint.Forms.Input{opts: opts}, form), do: not Visibility.hidden?(opts, form)
  defp shown?(_input, _form), do: false

  # The row's field has an input in the subform, and the row shows it
  defp row_shown?(%Brando.Blueprint.Forms.Subform{sub_fields: inputs}, changeset, {:row, subform, key, field}) do
    with %{opts: opts} <- Enum.find(inputs, &match?(%{name: name} when name != nil, &1) and to_string(&1.name) == field),
         {:ok, _kind, _assoc, rows} <- rows(changeset, subform),
         {_index, row} <- find_row(rows, key) do
      not Visibility.hidden?(opts, Phoenix.HTML.FormData.to_form(row, []))
    else
      _ -> false
    end
  end

  defp row_shown?(_subform, _changeset, _target), do: false

  # The block field a block text's key is in: `entry_<field>/…`
  defp block_field("entry_" <> rest), do: rest |> String.split("/", parts: 2) |> hd()
  defp block_field(_key), do: nil

  # How long the BlockFields have to answer with their texts
  @read_ms 10_000

  defp read(socket, work, units, keys) do
    %{id: form_id, entry: entry, translation: state} = socket.assigns
    run = System.unique_integer([:positive])
    targets = targets(state)
    previous = socket.assigns[:translation_fill]
    candidates = Enum.map(units, & &1.key)

    field_texts =
      for key <- candidates, form_target?(targets[key]), into: %{} do
        {key, field_value(socket.assigns.form.source, targets[key])}
      end

    by_field = block_targets(candidates, targets)

    for {field, block_targets} <- by_field do
      send_update(BlockField,
        id: "#{form_id}-blocks-#{field}",
        event: "translation_fill_start",
        run: run,
        field: field,
        targets: block_targets
      )
    end

    fill = %{
      run: run,
      status: :running,
      entry_id: entry.id,
      version_id: work.version_id,
      keys: candidates,
      progress: {0, 1},
      marks: marks_for(previous, work.version_id),
      baseline: field_texts,
      counts: nil,
      reading: %{
        work: work,
        units: units,
        all?: keys == :all,
        texts: field_texts,
        waiting: MapSet.new(Map.keys(by_field)),
        previous: previous
      }
    }

    socket = assign(socket, :translation_fill, fill)

    if by_field == %{} do
      begin(socket)
    else
      Phoenix.LiveView.send_update_after(
        BrandoAdmin.Components.Form,
        [id: form_id, action: :translation_fill_unanswered, run: run],
        @read_ms
      )

      socket
    end
  end

  @doc "A BlockField's block texts for run `run`, by key (`:error` for one it has not)."
  def block_texts_read(socket, run, field, texts) do
    case socket.assigns[:translation_fill] do
      %{run: ^run, reading: %{waiting: waiting}} = fill ->
        if MapSet.member?(waiting, field), do: take_block_texts(socket, fill, field, texts), else: socket

      _ ->
        socket
    end
  end

  defp take_block_texts(socket, %{reading: reading} = fill, field, texts) do
    reading = %{reading | texts: Map.merge(reading.texts, texts), waiting: MapSet.delete(reading.waiting, field)}
    socket = assign(socket, :translation_fill, %{fill | reading: reading})
    if MapSet.size(reading.waiting) == 0, do: begin(socket), else: socket
  end

  @doc "A BlockField did not answer with its texts: the run does not start."
  def unanswered(socket, run) do
    case socket.assigns[:translation_fill] do
      %{run: ^run, reading: %{previous: previous}} ->
        socket
        |> assign(:translation_fill, previous)
        |> toast(gettext("The blocks could not be read. Try again."))

      _ ->
        socket
    end
  end

  # The texts are read: what is sent, and the run
  defp begin(socket) do
    %{reading: reading} = fill = socket.assigns.translation_fill
    acknowledged = socket.assigns.translation.acknowledged

    units =
      Enum.flat_map(reading.units, fn unit ->
        text = Map.get(reading.texts, unit.key, :error)
        if sendable?(unit, text, reading.all?, acknowledged), do: [with_form_text(unit, text)], else: []
      end)

    case units do
      [] ->
        socket
        |> assign(:translation_fill, reading.previous)
        |> toast(gettext("Every open text has been reviewed or changed. Translate one with its own AI action."))

      units ->
        keys = Enum.map(units, & &1.key)

        fill = %{
          fill
          | keys: keys,
            marks: Map.drop(fill.marks, keys),
            baseline: Map.take(fill.baseline, keys),
            reading: nil
        }

        run(socket, fill, reading.work, units)
    end
  end

  # A text the form cannot read is not sent. Translating every text leaves
  # out an item ticked Reviewed and a text that is no longer the pending
  # version's: the editor has worked on them.
  defp sendable?(_unit, :error, _all?, _acknowledged), do: false
  defp sendable?(_unit, _text, false, _acknowledged), do: true

  defp sendable?(unit, text, true, acknowledged),
    do: unit.key not in acknowledged and same_text?(text, pending_text(unit))

  defp pending_text(unit), do: if(Map.has_key?(unit, :current), do: unit.current, else: unit.source)

  defp same_text?(a, b), do: blank_as_empty(a) == blank_as_empty(b)

  defp blank_as_empty(nil), do: ""
  defp blank_as_empty(text), do: text

  # A review brings the translation in the form up to date, not the stored one
  defp with_form_text(%{kind: "review"} = unit, text) when is_binary(text) do
    if String.trim(text) == "", do: Map.delete(unit, :current), else: Map.put(unit, :current, text)
  end

  defp with_form_text(%{kind: "review"} = unit, _text), do: Map.delete(unit, :current)
  defp with_form_text(unit, _text), do: unit

  defp run(socket, fill, work, units) do
    lv = self()
    form_id = socket.assigns.id
    run = fill.run

    progress = fn step ->
      send_update(lv, BrandoAdmin.Components.Form, id: form_id, action: :translation_fill_progress, run: run, step: step)
    end

    source_language = work.source_language
    language = work.language

    socket
    |> assign(:translation_fill, fill)
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

  @doc """
  Clears the marks and the status line of a run for a pending version that
  is no longer the one the form holds or the translation's pending one.
  """
  def refresh(socket) do
    case {socket.assigns[:translation_fill], Translation.version_id(socket.assigns), pending_id(socket.assigns)} do
      {%{version_id: version_id}, version_id, version_id} -> socket
      {%{status: :running} = fill, _, _} -> assign(socket, :translation_fill, %{fill | marks: %{}})
      {nil, _, _} -> socket
      _ -> assign(socket, :translation_fill, nil)
    end
  end

  defp pending_id(%{translation: %{pending: %{id: id}}}), do: id
  defp pending_id(_assigns), do: nil

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
         rows when is_list(rows) <- relation_rows(changeset, kind, name) do
      {:ok, kind, name, rows}
    else
      _ -> :error
    end
  end

  defp relation_rows(changeset, :assoc, name), do: Changeset.get_assoc(changeset, name, :changeset)
  defp relation_rows(changeset, :embed, name), do: Changeset.get_embed(changeset, name, :changeset)

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
