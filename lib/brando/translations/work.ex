defmodule Brando.Translations.Work do
  @moduledoc """
  A synchronized translation's open work as units a client translates, the
  token that ties an answer to what the client read, and the check of that
  answer.

  The units are read from the translation's pending version
  (`Brando.Translations.PendingVersion`), not the saved entry. Each has

    * `key` — the work item's path as `Brando.Translations.Sync` flattens it
      (`"title"`, `"entry_blocks/<sync_uid>/refs/body/text"`). Paths are the
      same in every language version, so the key is stable across reads.
    * `kind` — `"translate"` or `"review"`, answerable with text. The other
      open items (`"awaiting_translation"`, `"shared_update"`, `"relinked"`)
      are units too, with `answerable: false` and no text.
    * `label` — where the text is, as the form's work list names it
      (`Brando.Translations.Labels`).
    * `source` — the source's current text; `current` — the translation's
      text in the pending version, left out when it is the same as `source`
      (for *translate*, usually: the copy of the source's).
    * `format` — `"plain"`, `"html"` or `"markdown"`.
    * `block_uid` — for a text in a block, the translation's own block.

  A *review* unit also has `source_previous`, the source's text before the
  change that raised it (`Brando.Translations.WorkItem`), where it is known:
  not for a review raised before brando_239, and not in a batch whose unit
  would be too long with it (`batch/5`).

  `token/2` encodes the batch a client read: the entry, the language, and
  each answerable unit's key with a digest of its source text, signed so a
  changed token is refused (`Brando.Crypto.hmac/2`). `check/4` takes the
  token back with the client's answer and the units as they are now, and
  returns every problem at once: source text changed since the read, keys
  extra, missing or answered twice, markup or template placeholders lost.
  """
  alias Brando.Translations
  alias Brando.Translations.Labels
  alias Brando.Translations.Member
  alias Brando.Translations.Sync

  @answerable ~w(translate review)a
  @kind_order %{translate: 0, review: 0, shared_update: 1, relinked: 2, awaiting_translation: 3}

  @html_pattern ~r/<\/?[A-Za-z][^>]*>/u
  @placeholder_pattern ~r/\{\{.*?\}\}|\{%.*?%\}|<%.*?%>/su

  @token_version 1
  @digest_bytes 6
  @mac_bytes 16

  @type unit :: %{
          required(:key) => String.t(),
          required(:kind) => String.t(),
          required(:answerable) => boolean(),
          required(:label) => String.t(),
          optional(:format) => String.t(),
          optional(:source) => String.t() | nil,
          optional(:current) => String.t() | nil,
          optional(:source_previous) => String.t(),
          optional(:block_uid) => String.t()
        }

  @typedoc """
  What a token is for: the content type, the translation's id and its
  language. For a translation that does not exist yet (`prospective_units/3`),
  `id` is `{:new, source_id}`.
  """
  @type scope :: %{type: String.t(), id: integer() | {:new, integer()}, language: String.t()}

  @type problem :: %{key: String.t() | nil, code: String.t(), message: String.t()}

  ## Reading

  @doc """
  The open work of the synchronized translation `entry_id`, read from its
  pending version. Opening it resyncs a version computed against an older
  save of the translation, as opening the form does
  (`Brando.Translations.editor_state/2`); nothing else is written.

  Returns `{:ok, %{units: units, positions: positions, source_id: id,
  source_language: code, language: code, version_id: id | nil}}`, where
  `positions` places every path of the translation in the entry's order
  (`batch/5`), or `{:error, reason}`:
  `:not_synchronized` for a type that is not, `:unlinked` for an entry
  outside a group, `:source` for a group's source, `:independent` for a
  translation that no longer follows it, `:source_not_found`.
  """
  def translation_units(schema, entry_id) do
    case Translations.synchronized?(schema) && Translations.editor_state(schema, entry_id) do
      false ->
        {:error, :not_synchronized}

      nil ->
        {:error, :unlinked}

      %{member: %Member{role: :source}} ->
        {:error, :source}

      %{member: %Member{synchronized: false}} ->
        {:error, :independent}

      %{source: %{id: _}} = state ->
        read_translation(schema, entry_id, state)

      _ ->
        {:error, :source_not_found}
    end
  end

  defp read_translation(schema, entry_id, %{source: %{id: source_id}} = state) do
    with {:ok, entry} <- Translations.load_entry(schema, entry_id, with_deleted: true),
         {:ok, source} <- Translations.load_entry(schema, source_id) do
      {:ok, translation_units(entry, source, state)}
    else
      _ -> {:error, :source_not_found}
    end
  end

  @doc "Builds work from a fully loaded target, its authorized source and the pending version read with its membership."
  def translation_units(%schema{} = entry, %schema{id: id} = source, %{
        member: member,
        source: %{id: id, language: language},
        pending: pending
      }) do
    payload = if pending, do: Translations.pending_content(pending, entry), else: entry
    items = if pending, do: pending.work_items, else: []
    uids = Translations.module_uids([source, payload], schema)

    {units, positions} = open_work(schema, payload, source, items, uids)

    %{
      units: units,
      positions: positions,
      source_id: source.id,
      source_language: language,
      language: member.language,
      version_id: pending && pending.id
    }
  end

  @doc """
  The units a new translation of `source_id` would have
  (`prospective_units/3`) with their `positions`, as
  `{:ok, %{units: units, positions: positions}}`, or `{:error, :not_found}`.
  """
  def new_translation_units(schema, source_id) do
    case Translations.load_entry(schema, source_id) do
      {:ok, source} ->
        uids = Translations.module_uids([source], schema)
        positions = source |> Sync.flatten_entry(schema, nil, uids) |> positions()
        {:ok, %{units: prospective_units(schema, source, module_uids: uids), positions: positions}}

      _ ->
        {:error, :not_found}
    end
  end

  ## Units

  @doc """
  The open work of a translation: its pending version's `payload` (decoded,
  as `Brando.Translations.pending_content/2` gives it), its `source` entry
  and the version's `work_items`. Resolved items are left out.

  Text units come first, in the order the entry shows them, then the
  others. Options: `:module_uids` (`Brando.Translations.module_uids/2` of
  the source and the translation).
  """
  @spec units(module(), struct(), struct(), [map()], keyword()) :: [unit()]
  def units(schema, payload, source, work_items, opts \\ []) do
    schema |> open_work(payload, source, work_items, Keyword.get(opts, :module_uids, %{})) |> elem(0)
  end

  defp open_work(schema, payload, source, work_items, uids) do
    payload_rows = Sync.flatten_entry(payload, schema, nil, uids)
    current = for {path, :text, value} <- payload_rows, into: %{}, do: {path, value}
    order = positions(payload_rows)
    source_texts = for {path, :text, value} <- Sync.flatten_entry(source, schema, nil, uids), into: %{}, do: {path, value}
    ctx = context(schema, payload)

    units =
      work_items
      |> Enum.filter(&is_nil(Map.get(&1, :resolved_at)))
      |> Enum.uniq_by(& &1.path)
      |> Enum.sort_by(&{@kind_order[&1.kind], place(order, &1.path)})
      |> Enum.map(fn item ->
        if item.kind in @answerable,
          do:
            item.path
            |> text_unit(item.kind, Map.get(source_texts, item.path), Map.get(current, item.path), ctx)
            |> put_previous(item),
          else: other_unit(item.path, item.kind, ctx)
      end)

    {units, order}
  end

  defp positions(rows), do: rows |> Enum.with_index() |> Map.new(fn {{path, _, _}, index} -> {path, index} end)

  # Where a path is in the entry; one the entry no longer has goes last
  defp place(positions, path), do: {Map.get(positions, path, :infinity), path}

  @doc """
  The units a new translation of `source` would have: every text that is not
  empty, to translate, as `Brando.Translations.create_target/5` marks them.
  The copy keeps the source's block identities, so the keys are those the
  translation's work items will have. Units carry no `block_uid`: the blocks
  do not exist yet.
  """
  @spec prospective_units(module(), struct(), keyword()) :: [unit()]
  def prospective_units(schema, source, opts \\ []) do
    uids = Keyword.get(opts, :module_uids, %{})
    ctx = context(schema, source)

    for {path, :text, value} <- Sync.flatten_entry(source, schema, nil, uids), not blank?(value) do
      path |> text_unit(:translate, value, value, ctx) |> Map.delete(:block_uid)
    end
  end

  @doc """
  Where each of `keys` is, what its source holds and what the translation
  holds, for a review of an answer: `[%{key, label, format, source,
  current}]` in the order of `entry`, the translation (its pending version's
  content, as `Brando.Translations.pending_content/2` gives it), or the
  source itself for one not created yet. A key the entry does not have comes
  last, labelled by its path.
  """
  @spec describe(module(), struct(), struct(), [String.t()]) :: [map()]
  def describe(schema, source, entry, keys) do
    uids = Translations.module_uids([source, entry], schema)
    source_texts = for {path, :text, value} <- Sync.flatten_entry(source, schema, nil, uids), into: %{}, do: {path, value}
    entry_rows = Sync.flatten_entry(entry, schema, nil, uids)
    current = for {path, :text, value} <- entry_rows, into: %{}, do: {path, value}
    order = positions(entry_rows)
    ctx = context(schema, entry)

    keys
    |> Enum.uniq()
    |> Enum.sort_by(&place(order, &1))
    |> Enum.map(fn key ->
      target = Labels.target(key, ctx.blocks)

      %{
        key: key,
        label: Labels.label(target, ctx.labels),
        format: described_format(key, target, ctx),
        source: Map.get(source_texts, key),
        current: Map.get(current, key)
      }
    end)
  end

  defp described_format(key, target, ctx) do
    format(key, target, ctx)
  rescue
    _ -> "plain"
  end

  defp context(schema, entry) do
    %{
      entry: entry,
      blocks: Labels.block_index(schema, entry),
      labels: Labels.field_labels(schema),
      inputs: input_types(schema)
    }
  end

  defp text_unit(path, kind, source, current, ctx) do
    target = Labels.target(path, ctx.blocks)

    %{
      key: path,
      kind: to_string(kind),
      answerable: true,
      label: Labels.label(target, ctx.labels),
      format: format(path, target, ctx),
      source: source
    }
    |> put_current(source, current)
    |> put_block_uid(target)
  end

  defp put_previous(unit, %{kind: :review, source_previous: previous}) when is_binary(previous),
    do: Map.put(unit, :source_previous, previous)

  defp put_previous(unit, _item), do: unit

  defp put_current(unit, same, same), do: unit
  defp put_current(unit, _source, current), do: Map.put(unit, :current, current)

  defp other_unit(path, kind, ctx) do
    target = Labels.target(path, ctx.blocks)

    %{key: path, kind: to_string(kind), answerable: false, label: Labels.label(target, ctx.labels)}
    |> put_block_uid(target)
  end

  defp put_block_uid(unit, {:block, uid, _module, _rest}), do: Map.put(unit, :block_uid, uid)
  defp put_block_uid(unit, _target), do: unit

  ## Format

  # A field by its form input, a ref by its type, a variable by its type;
  # captions, alt texts, link texts and addresses are plain.
  defp format(_path, {:field, field}, ctx), do: input_format(ctx.inputs[field])
  # A subform row's field by its input; a page's variables (`vars/<key>/value`)
  # by their type
  defp format(_path, {:row, subform, row, field}, ctx) do
    case ctx.entry |> Map.get(String.to_existing_atom(subform)) |> List.wrap() |> Enum.find(&var_row?(&1, row)) do
      %Brando.Content.Var{} = var when field == "value" -> var_format(var)
      %Brando.Content.Var{} -> "plain"
      _ -> input_format(ctx.inputs["#{subform}/#{field}"])
    end
  rescue
    ArgumentError -> "plain"
  end

  defp format(path, {:block, _uid, _module, rest}, ctx) do
    ["entry_" <> _, identity | _] = String.split(path, "/")
    block = ctx.blocks[identity].block

    case rest do
      ["refs", name, "text"] -> block |> find(:refs, :name, name) |> ref_format()
      ["vars", key, "value"] -> block |> find(:vars, :key, key) |> var_format()
      ["rows", row, "vars", key, "value"] -> block |> row_var(row, key) |> var_format()
      _ -> "plain"
    end
  end

  defp var_row?(%Brando.Content.Var{key: key}, row), do: key == row
  defp var_row?(_row, _key), do: false

  defp input_format(:rich_text), do: "html"
  defp input_format(_type), do: "plain"

  defp ref_format(%{data: %{type: "text"}}), do: "html"
  defp ref_format(%{data: %{type: "markdown"}}), do: "markdown"
  defp ref_format(_ref), do: "plain"

  defp var_format(%{type: type}), do: var_type_format(type)
  defp var_format(_var), do: "plain"

  defp var_type_format(type) when type in [:rich_text, :html], do: "html"
  defp var_type_format(_type), do: "plain"

  defp find(struct, field, key, value) do
    case Map.get(struct, field) do
      list when is_list(list) -> Enum.find(list, &(to_string(Map.get(&1, key)) == value))
      _ -> nil
    end
  end

  # Rows by their identity, as `Sync` keys them
  defp row_var(block, row, key) do
    rows = if is_list(block.table_rows), do: block.table_rows, else: []

    case Enum.find(Sync.row_identities(rows), fn {_row, identity} -> identity == row end) do
      nil -> nil
      {found, _identity} -> find(found, :vars, :key, key)
    end
  end

  # Input types of the default form by field name, and a subform's by
  # "subform/field". A page's variables are keyed by their own key below.
  defp input_types(schema) do
    case schema.__form__() do
      %{tabs: tabs} ->
        for tab <- tabs, fieldset <- tab.fields, input <- fieldset.fields, reduce: %{} do
          acc -> put_input(acc, input)
        end

      _ ->
        %{}
    end
  end

  defp put_input(acc, %Brando.Blueprint.Forms.Input{name: name, type: type}), do: Map.put(acc, to_string(name), type)

  defp put_input(acc, %Brando.Blueprint.Forms.Subform{name: name, sub_fields: fields}) do
    Enum.reduce(fields, acc, fn
      %Brando.Blueprint.Forms.Input{name: field, type: type}, acc -> Map.put(acc, "#{name}/#{field}", type)
      _, acc -> acc
    end)
  end

  defp put_input(acc, _input), do: acc

  ## Batches

  @doc """
  The batch of answerable `units` (in the order `units/5` gives them) that
  comes after the key `after` in the entry, whose JSON stays within `bytes`
  with each unit's share of the token (`token_bytes/1`): at most
  `:max_units` (60). The first unit is taken whatever its size.

  A unit that takes more than `:alone` bytes (no limit by default) cannot be
  sent in any batch: it is listed without its text, not answerable, with
  `too_long: true` and a `reason`, and is left out of the batch's token. A
  review unit that fits only without its `source_previous` is sent without
  it.

  `after` is the last key of the previous batch, read from `positions`
  (`translation_units/2`), so a unit resolved since that batch was read does
  not move the next one: the key need not be open any more. nil, or a key
  the entry no longer has, starts from the first unit; the latter is
  `restarted`.

  Returns `%{units: batch, more: boolean, restarted: boolean}`.
  """
  @spec batch([unit()], map(), String.t() | nil, pos_integer(), keyword()) :: %{
          units: [unit()],
          more: boolean(),
          restarted: boolean()
        }
  def batch(units, positions, after_key, bytes, opts \\ []) do
    max_units = Keyword.get(opts, :max_units, 60)
    alone = Keyword.get(opts, :alone)
    known? = follows?(units, positions, after_key)

    rest =
      if known?,
        do: Enum.filter(units, &(place(positions, &1.key) > place(positions, after_key))),
        else: units

    {batch, _size} =
      Enum.reduce_while(rest, {[], 0}, fn unit, {acc, size} ->
        {unit, unit_size} = sized(unit, alone)

        cond do
          acc == [] -> {:cont, {[unit], unit_size}}
          length(acc) >= max_units or size + unit_size > bytes -> {:halt, {acc, size}}
          true -> {:cont, {[unit | acc], size + unit_size}}
        end
      end)

    %{units: Enum.reverse(batch), more: length(batch) < length(rest), restarted: after_key != nil and not known?}
  end

  defp sized(unit, alone) do
    size = unit_bytes(unit)

    cond do
      is_nil(alone) or size <= alone ->
        {unit, size}

      Map.has_key?(unit, :source_previous) ->
        sized(Map.delete(unit, :source_previous), alone)

      true ->
        unit = too_long(unit)
        {unit, unit_bytes(unit)}
    end
  end

  defp unit_bytes(unit), do: byte_size(Jason.encode!(unit)) + 1 + token_bytes(unit)

  defp too_long(unit) do
    unit
    |> Map.take([:key, :kind, :label, :format, :block_uid])
    |> Map.merge(%{
      answerable: false,
      too_long: true,
      reason:
        "This text is too long to be read with translation_work, and cannot be translated here. " <>
          "Translate it in the entry's form in the admin."
    })
  end

  @doc """
  Whether `batch/5` continues after `after_key`: false for nil, or a key
  neither in the entry nor among the `units`, from which it starts over.
  """
  @spec follows?([unit()], map(), String.t() | nil) :: boolean()
  def follows?(_units, _positions, nil), do: false
  def follows?(units, positions, key), do: Map.has_key?(positions, key) or Enum.any?(units, &(&1.key == key))

  @doc """
  At most the bytes an answerable unit adds to its batch's token: its key and
  source digest, encoded.
  """
  @spec token_bytes(unit()) :: non_neg_integer()
  def token_bytes(%{answerable: true, key: key}), do: div((byte_size(key) + 24) * 4, 3) + 1
  def token_bytes(_unit), do: 0

  ## Token

  @doc """
  The token for a batch of answerable `units` of `scope`: opaque to the
  client, which sends it back with its answer.
  """
  @spec token(scope(), [unit()]) :: String.t()
  def token(%{type: type, id: id, language: language}, units) do
    entries = for %{answerable: true, key: key, source: source} <- units, do: {key, source_digest(source)}
    body = :erlang.term_to_binary({@token_version, to_string(type), id, to_string(language), entries}, compressed: 9)
    Base.url_encode64(mac(body) <> body, padding: false)
  end

  defp source_digest(source), do: binary_part(:crypto.hash(:sha256, :erlang.term_to_binary(source)), 0, @digest_bytes)

  defp mac(body), do: binary_part(Brando.Crypto.hmac(body, "translation work"), 0, @mac_bytes)

  # Only a body this module signed is decoded.
  defp decode(token, %{type: type, id: id, language: language}) when is_binary(token) do
    with {:ok, <<mac::binary-size(@mac_bytes), body::binary>>} <- Base.url_decode64(token, padding: false),
         true <- Plug.Crypto.secure_compare(mac, mac(body)),
         {@token_version, type_, id_, language_, entries} <- :erlang.binary_to_term(body, [:safe]),
         true <- {type_, id_, language_} == {to_string(type), id, to_string(language)} do
      {:ok, entries}
    else
      _ -> :error
    end
  end

  defp decode(_token, _scope), do: :error

  ## Check

  @doc """
  Checks an answer to a batch against the token the client read it with.

  `answer` holds `texts` (`%{key => text}`) and `reviewed` (keys whose text
  is kept as it is). `units` are the units of `scope` as they are now (all
  of them, not only the batch). Returns `:ok`, or `{:error, problems}` with
  every problem found, each naming its unit:

    * `stale` (no key) — the token is not one for this entry and language,
      or was changed; read the work again
    * `source_changed` — the source text of an answered unit changed since
      the client read it, or the unit is no longer open
    * `extra` — a key that was not in the batch
    * `missing` — a key of the batch answered neither with a text nor as
      reviewed
    * `duplicate` — a key answered twice
    * `malformed` (no key) — `texts` is not an object of texts by key, or
      `reviewed` not a list of keys
    * `not_text` / `blank` — an answer that is not a string, or is empty for
      a source text that is not
    * `html_changed` / `placeholders_changed` — the text lost or changed the
      source's HTML tags or template placeholders (`{{ }}`, `{% %}`, `<% %>`)
  """
  @spec check(String.t(), scope(), [unit()], %{texts: map(), reviewed: [String.t()]}) :: :ok | {:error, [problem()]}
  def check(token, scope, units, answer) do
    case decode(token, scope) do
      {:ok, entries} ->
        texts = Map.get(answer, :texts) || %{}
        reviewed = Map.get(answer, :reviewed) || []

        case shape_problems(texts, reviewed) ++ problems(entries, units, texts, reviewed) do
          [] -> :ok
          problems -> {:error, problems}
        end

      :error ->
        {:error,
         [
           problem(
             nil,
             "stale",
             "This source_digest is not one translation_work gave for this entry and language. Read the work again."
           )
         ]}
    end
  end

  # An answer the model shaped wrongly is a problem to tell it, not a crash
  defp shape_problems(texts, reviewed) do
    [
      {is_map(texts) and Enum.all?(Map.keys(texts), &is_binary/1), "texts must be an object of {key: translation}."},
      {is_list(reviewed) and Enum.all?(reviewed, &is_binary/1), "reviewed must be a list of keys."}
    ]
    |> Enum.reject(&elem(&1, 0))
    |> Enum.map(&problem(nil, "malformed", elem(&1, 1)))
  end

  defp problems(entries, units, texts, reviewed) when not (is_map(texts) and is_list(reviewed)) do
    texts = if is_map(texts), do: texts, else: %{}
    reviewed = if is_list(reviewed), do: reviewed, else: []
    problems(entries, units, texts, reviewed)
  end

  defp problems(entries, units, texts, reviewed) do
    read = Map.new(entries)
    read_keys = Enum.map(entries, &elem(&1, 0))
    now = for %{answerable: true} = unit <- units, into: %{}, do: {unit.key, unit}
    answered = Map.keys(texts) ++ reviewed
    counts = Enum.frequencies(answered)

    duplicate =
      for {key, count} <- Enum.sort(counts), count > 1 do
        problem(key, "duplicate", "Answered more than once. Give a text in texts or list it in reviewed, not both.")
      end

    extra =
      for key <- Enum.uniq(answered), not Map.has_key?(read, key) do
        problem(key, "extra", "Not a unit of the batch this source_digest was read with. Leave it out.")
      end

    missing =
      for key <- read_keys, not Map.has_key?(counts, key) do
        problem(key, "missing", "Not answered. Give its translation in texts, or list it in reviewed to keep it.")
      end

    stale =
      for key <- read_keys, Map.has_key?(counts, key), stale?(now[key], read[key]) do
        problem(
          key,
          "source_changed",
          "The source text changed since you read it, or it no longer needs translation. Read translation_work again."
        )
      end

    texts_problems =
      for key <- read_keys,
          Map.has_key?(texts, key),
          unit = now[key],
          unit != nil,
          not stale?(unit, read[key]),
          problem <- text_problems(unit, texts[key]),
          do: problem

    duplicate ++ extra ++ missing ++ stale ++ texts_problems
  end

  @doc """
  The problems of one translated `text` for an answerable `unit`, as
  `check/4` finds them per unit: `not_text`, `blank`, `html_changed`,
  `placeholders_changed`. An empty list when the text keeps what the source
  has. For an answer that did not come with a token, such as the admin's
  Translate with AI.
  """
  @spec answer_problems(unit(), term()) :: [problem()]
  def answer_problems(unit, text), do: text_problems(unit, text)

  defp stale?(nil, _digest), do: true
  defp stale?(unit, digest), do: source_digest(unit.source) != digest

  defp text_problems(unit, text) when is_binary(text) do
    source = unit.source || ""

    if String.trim(text) == "" and not blank?(source),
      do: [problem(unit.key, "blank", "The translation is empty. Translate the text, or list the key in reviewed.")],
      else: html_problems(unit.key, source, text) ++ placeholder_problems(unit.key, source, text)
  end

  defp text_problems(unit, _text), do: [problem(unit.key, "not_text", "The translation must be a string.")]

  defp html_problems(key, source, text) do
    source_tags = @html_pattern |> Regex.scan(source) |> List.flatten()

    if source_tags != [] and source_tags != @html_pattern |> Regex.scan(text) |> List.flatten() do
      [
        problem(
          key,
          "html_changed",
          "HTML tags or attributes changed. Keep every tag of the source, in order, with its attributes exactly as they are: " <>
            Enum.join(source_tags, " ")
        )
      ]
    else
      []
    end
  end

  defp placeholder_problems(key, source, text) do
    expected = @placeholder_pattern |> Regex.scan(source) |> List.flatten() |> Enum.sort()
    got = @placeholder_pattern |> Regex.scan(text) |> List.flatten() |> Enum.sort()

    if expected == got,
      do: [],
      else: [
        problem(
          key,
          "placeholders_changed",
          "Template placeholders changed. Keep each exactly as the source has it: " <>
            if(expected == [], do: "the source has none", else: Enum.join(expected, " "))
        )
      ]
  end

  defp problem(key, code, message), do: %{key: key, code: code, message: message}

  @doc """
  The HTML tags in `text`, in order, with their attributes, as `check/4`
  compares them.
  """
  @spec html_tags(String.t()) :: [String.t()]
  def html_tags(text) when is_binary(text), do: @html_pattern |> Regex.scan(text) |> List.flatten()

  @doc """
  The template placeholders (`{{ }}`, `{% %}`, `<% %>`) in `text`, each once,
  as `check/4` matches them.
  """
  @spec placeholders(String.t()) :: [String.t()]
  def placeholders(text) when is_binary(text),
    do: @placeholder_pattern |> Regex.scan(text) |> List.flatten() |> Enum.uniq()

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(nil), do: true
  defp blank?(_value), do: false
end
