defmodule Brando.Villain.TemplateView do
  @moduledoc """
  What a Liquid template reads of data it did not write: an entry and its
  preloads, `identity`, `navigation`, `request`, ref data and a datasource's
  `entries`.

  It prints the way a `string` var does. A string is HTML-escaped when it is
  read, with its braces as character references, so markup or Liquid in a
  field is printed as text. A field its schema's forms draw as rich text
  (`Brando.RichText.fields_for_printing/1`), a text ref's `text` and a
  placement's caption arrive sanitized, to print as markup, each value
  sanitized once in a render (`sanitize_rich_text/1`). So does a subform
  row's field that a form of the row's owner draws as rich text
  (`Brando.RichText.row_fields_for_printing/2`): the rows' views carry those
  names, also through a filter that selects or reorders the rows
  (`keep_rich_rows/2`). A template opts in to a plain field's markup with the `raw` filter
  (`Brando.Villain.Filters.raw/2`). A field of rendered blocks is escaped too,
  and `raw` prints it as it is stored (`read_as_rendered_blocks/2`).

  The view is a `Liquex.Drop` around the value, resolved one key at a time, so
  a render pays only for what its templates read and a heavy preload it never
  touches costs nothing.

  Credentials do not get through it: a `Brando.Users.User` shows only
  `@user_fields`, and no struct or map shows a field with a credential word in
  its name. Names an author chose are no credentials: a block's ref names and
  the keys of processed maps are read as they are.

  Tags and filters get the value itself, with the same fields left out: a tag
  with `eval/2`, a filter from `Brando.Villain.Filters.apply/4`, which puts the
  filter's result back in a view. HEEx escapes what it prints and reads the
  plain value (`Brando.Villain.raw_context/2`).
  """

  @behaviour Liquex.Drop

  alias Brando.Captions
  alias Brando.Content.Var
  alias Brando.Images.Image
  alias Brando.Users.User
  alias Brando.Videos.Video
  alias Brando.Villain.Blocks.PictureBlock
  alias Brando.Villain.Blocks.TextBlock
  alias Brando.Villain.Blocks.VideoBlock
  alias Brando.Villain.InertLiquid
  alias Brando.Villain.Markdown
  alias Brando.Villain.Parser
  alias Liquex.Context

  # `rich`: the fields of a subform row that its owner's forms draw as rich text
  defstruct [:value, mode: :escape, rich: []]

  @type mode :: :escape | :processed | :raw | :names
  @type t :: %__MODULE__{value: map(), mode: mode(), rich: [atom()]}

  # In the context's private data, where no template can read or set it
  @raw_flag :brando_template_view_raw

  # Text read as rich text (`read_as_rich_text/1`), each with the stored HTML of
  # a field of rendered blocks it was read from (`read_as_rendered_blocks/2`)
  # or `true`, and how deep in renders (`rich_text_scope/1`) the process is
  @rich_texts {__MODULE__, :rich_texts}
  @rich_texts_before {__MODULE__, :rich_texts_before}
  @rich_depth {__MODULE__, :rich_text_depth}
  # Marked outside any render, as a context is made: kept for the renders that
  # use it, in two sets of at most this many, the current one and the one before
  @rich_texts_outside 1_000
  # Rich text sanitized in a render (`sanitize_rich_text/1`), until the
  # outermost one ends
  @sanitized {__MODULE__, :sanitized_rich_texts}

  @user_fields ~w(id name email language role avatar active job_title same_as inserted_at updated_at deleted_at)a
  @user_keys @user_fields ++ Enum.map(@user_fields, &Atom.to_string/1)

  @credential_words ~w(
    password passwords passwd passwordhash hashedpassword secret secrets secretkey clientsecret token accesstoken
    authtoken credential credentials api_key api_keys api-key apikey totp recovery_code recovery_codes recovery-code
  )

  @values [Date, Time, DateTime, NaiveDateTime, Decimal, Range]

  # A placement's caption is rich text, a library title plain:
  # `Brando.Captions.caption_html/1` tells them apart.
  @captioned [Image, Video, PictureBlock.Data, VideoBlock.Data]

  @filters_giving_markup [:markdown, :json_ld, :inspect, :raw, :srcset, :size, :large, :xlarge]

  # Their text has what a view had as references as plain characters again, and
  # is no JSON that needs its braces.
  @filters_decoding_text [:strip_html, :url_decode]

  @doc """
  `value` as a template reads it. Mode `:escape` escapes the strings in it as
  they are read. Mode `:processed` is for what the parser has already escaped
  (a block's processed vars, its table rows): strings as they are, lists and
  plain maps the same, keys as an author named them, and a struct read in
  `:escape`. Mode `:names` is for the map of a block's refs: its keys as an
  author named them, what they hold in `:escape`. Mode `:raw` is for text no
  HTML is made of (a Markdown template) and for what a tag reads, with
  credentials left out all the same.
  """
  @spec wrap(term(), mode()) :: term()
  def wrap(value, mode \\ :escape)
  def wrap(%__MODULE__{} = view, _mode), do: view
  def wrap(value, mode) when is_binary(value) and mode in [:escape, :names], do: escape(value)
  def wrap(value, _mode) when is_binary(value), do: value
  def wrap(value, mode) when is_list(value), do: Enum.map(value, &wrap(&1, mode))
  def wrap(%Ecto.Association.NotLoaded{}, _mode), do: nil
  def wrap(%struct{} = value, _mode) when struct in @values, do: value
  def wrap(value, _mode) when is_map(value) and map_size(value) == 0, do: value
  def wrap(%_{} = value, :processed), do: %__MODULE__{value: value, mode: :escape}
  def wrap(value, mode) when is_map(value), do: %__MODULE__{value: value, mode: mode}
  def wrap(value, _mode), do: value

  @doc """
  An atom as its text, and each atom in a list, as a template reads a field.
  Liquid has no atoms and Liquex compares none equal to text, so an entry's
  `status` or an `Ecto.Enum` field read as text makes
  `{% if e.status == "draft" %}` hold, and prints as the atom did. `nil`,
  `true` and `false` stay as they are.
  """
  @spec atom_text(term()) :: term()
  def atom_text(value) when is_boolean(value) or is_nil(value), do: value
  def atom_text(value) when is_atom(value), do: Atom.to_string(value)
  def atom_text(value) when is_list(value), do: Enum.map(value, &atom_text/1)
  def atom_text(value), do: value

  @doc "`value` as `wrap/2` gives it for a template rendering in `context`."
  @spec wrap_for(term(), Context.t()) :: term()
  def wrap_for(value, %Context{} = context), do: wrap(value, read_mode(:escape, context))

  @doc """
  A multi module's entries: child blocks, whose `vars` the parser has processed.
  """
  @spec wrap_children([map()], Context.t()) :: [t()]
  def wrap_children(children, %Context{} = context) do
    Enum.map(children, fn %{vars: vars} = child ->
      %{child | vars: %__MODULE__{value: vars, mode: :processed}}
      |> Map.replace_lazy(:refs, &wrap(&1, :names))
      |> wrap_for(context)
    end)
  end

  @impl Liquex.Drop
  def fetch(%__MODULE__{value: value, mode: :names}, key, %Context{} = context) do
    with {:ok, field} <- Liquex.Indifferent.fetch(value, key) do
      {:ok, wrap_for(field, context)}
    end
  end

  def fetch(%__MODULE__{value: value, mode: mode} = view, key, %Context{} = context) do
    with false <- hidden?(value, key, mode),
         {:ok, field} <- Liquex.Indifferent.fetch(value, key) do
      {:ok, view |> read(key, field, read_mode(mode, context)) |> atoms_as_text(context)}
    else
      _ -> :error
    end
  end

  # A view resolved on every read: the cache key would hash the whole value.
  @impl Liquex.Drop
  def cacheable?(_view), do: false

  @doc """
  Evaluates a tag's `argument` to the value itself, its text unescaped. A tag
  escapes what it prints, or passes it to something that does.
  """
  @spec eval(term(), Context.t()) :: term()
  def eval(argument, %Context{private: private} = context) do
    {value, _context} = Liquex.Argument.eval(argument, %{context | private: Map.put(private, @raw_flag, true)})
    unwrap(value)
  end

  @doc """
  The value in a view, with credentials left out: a list's items, and a keyword
  argument's value, too. A map of names an author chose stays whole.
  """
  @spec unwrap(term()) :: term()
  def unwrap(%__MODULE__{value: value, mode: mode}) when mode in [:processed, :names] and not is_struct(value), do: value
  def unwrap(%__MODULE__{value: value}), do: without_credentials(value)
  def unwrap(value) when is_list(value), do: Enum.map(value, &unwrap/1)
  def unwrap({key, value}), do: {key, unwrap(value)}
  def unwrap(value), do: value

  @doc """
  What a filter's result is read as: `:escape` if any view in `value` escapes,
  else the mode they have, nil with no view. A block's ref names are not its text,
  so `:names` reads as `:escape`.
  """
  @spec view_mode(term()) :: mode() | nil
  def view_mode(%__MODULE__{mode: :names}), do: :escape
  def view_mode(%__MODULE__{mode: mode}), do: mode

  def view_mode(value) when is_list(value) do
    modes = value |> Enum.map(&view_mode/1) |> Enum.reject(&is_nil/1)
    if :escape in modes, do: :escape, else: List.first(modes)
  end

  def view_mode({_key, value}), do: view_mode(value)
  def view_mode(_value), do: nil

  @doc """
  A filter's result, given `mode`, the mode of the view it read (`view_mode/1`).
  It goes back in a view of that mode, and a record or map it returned goes in
  one whatever it read. Text stays as a filter that makes markup or returns
  `{:safe, html}` gave it, and text from any filter starts no Liquid in the
  final pass, except in a Markdown template, which has none.
  """
  @spec filter_result(term(), atom(), mode() | nil, Context.t()) :: term()
  def filter_result({:safe, html}, _filter, _mode, context), do: html |> IO.iodata_to_binary() |> inert(context)

  def filter_result(result, filter, _mode, context) when is_binary(result) and filter in @filters_giving_markup,
    do: inert(result, context)

  # A `{` written before a tag can reach it (`{ {{- x }}`): no brace in this text
  # makes a delimiter, with the template's or through a later filter.
  def filter_result(result, filter, mode, context) when is_binary(result) and filter in @filters_decoding_text do
    text = filter_result(result, :text, mode, context)

    if Markdown.template_context?(context),
      do: text,
      else: text |> InertLiquid.encode_all() |> InertLiquid.close_delimiter()
  end

  def filter_result(result, _filter, nil, context),
    do: result |> atom_text() |> wrap_records(context) |> inert(context)

  def filter_result(result, _filter, mode, context),
    do: result |> atom_text() |> wrap(read_mode(mode, context)) |> inert(context)

  @doc """
  Gives each subform row in a filter's `result` the rich-text fields it had
  in the filter's `inputs` (the value and arguments, `with_rich_rows/3`), so
  a row a filter selects or reorders (`first`, `reverse`, `sort`, `where`)
  prints as it does in a loop. A filter reads the rows unwrapped, and a
  value it computes is no row it was given.
  """
  @spec keep_rich_rows(term(), term()) :: term()
  def keep_rich_rows(result, inputs) do
    case rich_rows(inputs, %{}) do
      rows when map_size(rows) == 0 -> result
      rows -> put_rich_rows(result, rows)
    end
  end

  defp rich_rows(%__MODULE__{rich: [_ | _] = rich} = view, acc), do: Map.put(acc, unwrap(view), rich)
  defp rich_rows(list, acc) when is_list(list), do: Enum.reduce(list, acc, &rich_rows/2)
  defp rich_rows({_key, value}, acc), do: rich_rows(value, acc)
  defp rich_rows(_value, acc), do: acc

  defp put_rich_rows(%__MODULE__{value: value} = view, rows) do
    case Map.fetch(rows, value) do
      {:ok, rich} -> %{view | rich: rich}
      :error -> view
    end
  end

  defp put_rich_rows(list, rows) when is_list(list), do: Enum.map(list, &put_rich_rows(&1, rows))
  defp put_rich_rows(value, _rows), do: value

  defp wrap_records(value, context) when is_map(value), do: wrap_for(value, context)
  defp wrap_records(value, context) when is_list(value), do: Enum.map(value, &wrap_records(&1, context))
  defp wrap_records(value, _context), do: value

  defp inert(value, context) when is_list(value), do: Enum.map(value, &inert(&1, context))

  defp inert(text, context) when is_binary(text) do
    if Markdown.template_context?(context), do: text, else: InertLiquid.encode_delimiters(text)
  end

  defp inert(value, _context), do: value

  @doc """
  Marks `text` as read as rich text, and returns it: sanitized markup whose
  typed characters are entities, which was not escaped when read. `raw` leaves
  such text as it is (`Brando.Villain.Filters.raw/2`), and a filter given it
  returns text, or a list of texts, marked the same (`keep_rich_text/2`), so it
  holds through `assign` too. Text a template builds from printed output
  (`capture`) is new text, and not marked, unless it is the same text.

  Text without an entity, a `%` or a `<` is not marked: `raw` has nothing in
  it to decode, nor `url_decode` (`sanitize_decoded/2`), and `markdown` no
  markup to keep (`rich_text_markup/1`).

  The mark is the text itself, kept for the process: inside a render
  (`rich_text_scope/1`) until the outermost one ends, outside any render (a
  context made before its renders) at least the last #{@rich_texts_outside}
  marks. Other text with the same characters counts as marked too: a plain
  field whose escaped text equals rich text read in the same render is left
  as it is by `raw`.
  """
  @spec read_as_rich_text(term()) :: term()
  def read_as_rich_text(text) when is_binary(text) do
    if String.contains?(text, ["&", "%", "<"]), do: mark_rich_text(text)
    text
  end

  def read_as_rich_text(value), do: value

  # Outside a render, a full set becomes the one before it, so a lookup still
  # finds the newest marks and no more than two sets are kept. A mark is not
  # replaced: a filter that passes text on unchanged (`strip`) leaves the
  # stored HTML it was read from with it.
  defp mark_rich_text(text, source \\ true) do
    texts = Process.get(@rich_texts, %{})

    if Process.get(@rich_depth, 0) == 0 and map_size(texts) >= @rich_texts_outside do
      Process.put(@rich_texts_before, texts)
      Process.put(@rich_texts, %{text => source})
    else
      Process.put(@rich_texts, Map.put_new(texts, text, source))
    end
  end

  @doc """
  Marks `text`, a field of rendered blocks as it was read (escaped), as read
  from the stored `html`, and returns it: `raw` prints that HTML as it is
  (`rendered_blocks_html/1`). A filter given it returns text marked as rich
  text (`keep_rich_text/2`), which `raw` leaves escaped, so what an editor
  typed in a block stays text.
  """
  @spec read_as_rendered_blocks(String.t(), String.t()) :: String.t()
  def read_as_rendered_blocks(text, html) do
    if String.contains?(text, "&"), do: mark_rich_text(text, html)
    text
  end

  @doc """
  The stored HTML of the field of rendered blocks `text` was read from
  (`read_as_rendered_blocks/2`), or nil.
  """
  @spec rendered_blocks_html(term()) :: String.t() | nil
  def rendered_blocks_html(text) when is_binary(text) do
    case mark(text) do
      html when is_binary(html) -> html
      _ -> nil
    end
  end

  def rendered_blocks_html(_value), do: nil

  @doc """
  `text` sanitized again as rich text is when read (`sanitize_rich_text/1`)
  when it was read as rich text (`read_as_rich_text/1`), as rich text or as a
  filter's result from it, and nil for any other text, a field of rendered
  blocks as it was read included. For `markdown`, which keeps rich text's
  markup rather than reading it as Markdown.
  """
  @spec rich_text_markup(term()) :: String.t() | nil
  def rich_text_markup(text) when is_binary(text) do
    if mark(text) == true, do: sanitize_rich_text(text)
  end

  def rich_text_markup(_value), do: nil

  @doc """
  `text` sanitized as rich text is when read (`Brando.RichText.render_html/1`),
  with every brace a character reference. In a render (`rich_text_scope/1`)
  a value is sanitized once: what it gave is kept, with the value and as
  sanitized itself, until the outermost render ends. Outside a render
  nothing is kept.
  """
  @spec sanitize_rich_text(term()) :: term()
  def sanitize_rich_text(text) when is_binary(text) do
    if Process.get(@rich_depth, 0) == 0 do
      sanitize(text)
    else
      case Process.get(@sanitized, %{}) do
        %{^text => clean} ->
          clean

        sanitized ->
          clean = sanitize(text)
          Process.put(@sanitized, sanitized |> Map.put(text, clean) |> Map.put(clean, clean))
          clean
      end
    end
  end

  def sanitize_rich_text(value), do: sanitize(value)

  defp sanitize(value), do: value |> Brando.RichText.render_html() |> InertLiquid.encode_all()

  @doc "Whether `text` was read as rich text (`read_as_rich_text/1`)."
  @spec read_as_rich_text?(term()) :: boolean()
  def read_as_rich_text?(text) when is_binary(text), do: mark(text) != nil
  def read_as_rich_text?(_value), do: false

  defp mark(text) do
    with nil <- Process.get(@rich_texts, %{})[text] do
      Process.get(@rich_texts_before, %{})[text]
    end
  end

  @doc """
  A filter's `result` marked as read as rich text when one of its `inputs`
  (the value and arguments) was: text, or each text in a list it returned
  (`split`), nested lists too. Text that is one of the inputs that was not
  read as rich text is that input passed on (`default`, `first`, `concat`),
  and stays unmarked.
  """
  @spec keep_rich_text(term(), term()) :: term()
  def keep_rich_text(result, inputs) when is_binary(result) or is_list(result) do
    if rich_input?(inputs), do: mark_texts(result, plain_texts(inputs, [])), else: result
  end

  def keep_rich_text(result, _inputs), do: result

  defp mark_texts(list, plain) when is_list(list), do: Enum.map(list, &mark_texts(&1, plain))
  defp mark_texts(text, plain) when is_binary(text), do: if(text in plain, do: text, else: read_as_rich_text(text))
  defp mark_texts(value, _plain), do: value

  # The inputs' texts that were not read as rich text
  defp plain_texts(list, plain) when is_list(list), do: Enum.reduce(list, plain, &plain_texts/2)
  defp plain_texts({_key, value}, plain), do: plain_texts(value, plain)
  defp plain_texts(text, plain) when is_binary(text), do: if(read_as_rich_text?(text), do: plain, else: [text | plain])
  defp plain_texts(_value, plain), do: plain

  defp rich_input?(list) when is_list(list), do: Enum.any?(list, &rich_input?/1)
  defp rich_input?({_key, value}), do: rich_input?(value)
  defp rich_input?(value), do: read_as_rich_text?(value)

  @doc """
  The text a decoding filter (`url_decode`) gave, sanitized as rich text is
  when read (`Brando.RichText.render_html/1`) when one of its `inputs` was read
  as rich text: decoded, what an editor typed in it can be markup.
  """
  @spec sanitize_decoded(term(), term()) :: term()
  def sanitize_decoded(result, inputs) when is_binary(result) do
    if rich_input?(inputs), do: Brando.RichText.render_html(result), else: result
  end

  def sanitize_decoded(result, _inputs), do: result

  @doc """
  Runs `fun` as a render: text marked as read as rich text in it
  (`read_as_rich_text/1`) is let go when the outermost render ends, and text
  marked before it is kept. So is the rich text sanitized in it
  (`sanitize_rich_text/1`).
  """
  @spec rich_text_scope((-> result)) :: result when result: term()
  def rich_text_scope(fun) do
    case Process.get(@rich_depth, 0) do
      0 ->
        outside = Process.get(@rich_texts)
        Process.put(@rich_depth, 1)

        try do
          fun.()
        after
          Process.delete(@rich_depth)
          Process.delete(@sanitized)
          if outside, do: Process.put(@rich_texts, outside), else: Process.delete(@rich_texts)
        end

      depth ->
        Process.put(@rich_depth, depth + 1)

        try do
          fun.()
        after
          Process.put(@rich_depth, depth)
        end
    end
  end

  @doc """
  The `key` field of each of `items`, as a template reads it on the item
  (`{{ item.key }}`), for the `map` filter.
  """
  @spec map(list(), term(), Context.t()) :: list()
  def map(items, key, %Context{} = context) do
    Enum.map(items, fn
      %__MODULE__{} = view ->
        case fetch(view, key, context) do
          {:ok, field} -> field
          :error -> nil
        end

      item ->
        Liquex.Indifferent.get(item, key, nil)
    end)
  end

  @doc """
  A plain map's pairs as a loop reads them, `[key, value]` as Liquex gives a
  map's: no hidden field, the key escaped, the value as this view reads it.
  """
  @spec pairs(t()) :: [list()]
  def pairs(%__MODULE__{value: value, mode: mode}) do
    {key_mode, field_mode} =
      case mode do
        :raw -> {:raw, :raw}
        :names -> {:escape, :escape}
        mode -> {:escape, mode}
      end

    for {key, field} <- value, not hidden?(value, key, mode) do
      [key |> atom_text() |> wrap(key_mode), field |> atom_text() |> wrap(field_mode)]
    end
  end

  @doc """
  The number of a plain map's pairs a loop reads (`pairs/1`), none hidden
  from a template, and nil for a view of a record.
  """
  @spec pair_count(t()) :: non_neg_integer() | nil
  def pair_count(%__MODULE__{value: value}) when is_struct(value), do: nil

  def pair_count(%__MODULE__{value: value, mode: mode}),
    do: Enum.count(value, fn {key, _} -> not hidden?(value, key, mode) end)

  @doc """
  `value` with every user reduced to `@user_fields` and every credential field
  emptied, all the way down, for printing it whole (`{% inspect %}`).
  """
  @spec printable(term()) :: term()
  def printable(%__MODULE__{value: value}), do: printable(value)
  def printable(%struct{} = value) when struct in @values, do: value
  def printable(%User{} = user), do: user |> without_credentials() |> printable_fields()
  def printable(value) when is_map(value), do: value |> without_credentials() |> printable_fields()
  def printable(value) when is_list(value), do: Enum.map(value, &printable/1)
  def printable({key, value}), do: {key, printable(value)}
  def printable(value), do: value

  defp printable_fields(map), do: :maps.map(fn _key, value -> printable(value) end, map)

  # Only `:escape` changes text it reads: a tag and a Markdown template read it raw
  defp read_mode(:escape, %Context{private: private} = context) do
    if Map.get(private, @raw_flag) == true or Markdown.template_context?(context), do: :raw, else: :escape
  end

  defp read_mode(mode, _context), do: mode

  # A tag gets the atom itself
  defp atoms_as_text(field, %Context{private: %{@raw_flag => true}}), do: field
  defp atoms_as_text(field, _context), do: atom_text(field)

  defp read(view, key, field, :escape) when is_binary(field), do: read_text(view, key, field)
  defp read(%{value: value}, key, field, mode), do: field |> wrap(mode) |> with_rich_rows(value, key)

  defp read_text(%{value: %struct{} = value, rich: rich}, key, text) do
    cond do
      plain?(text) ->
        text

      # A rich caption is not escaped when read; a plain title is, and `raw`
      # reads it as it reads other escaped text
      struct in @captioned and to_string(key) in ["title", "caption"] ->
        html = Captions.caption_html(text)
        if Captions.rich?(text), do: read_as_rich_text(html), else: html

      rich_text?(value, key) or named?(rich, key) ->
        text |> sanitize_rich_text() |> read_as_rich_text()

      # Escaped as a plain field is, and `raw` prints the HTML as it is stored
      rendered_blocks?(value, key) ->
        text |> escape() |> read_as_rendered_blocks(text)

      true ->
        escape(text)
    end
  end

  defp read_text(_view, _key, text), do: escape(text)

  # A blueprint's subform rows, each view given the fields its owner's forms
  # draw as rich text
  defp with_rich_rows(rows, %struct{}, key) when is_list(rows) do
    case rich_row_fields(rows, struct, key) do
      [] -> rows
      fields -> Enum.map(rows, &put_rich(&1, fields))
    end
  end

  defp with_rich_rows(%__MODULE__{value: %_{}} = row, %struct{}, key) do
    case rich_row_fields([row], struct, key) do
      [] -> row
      fields -> put_rich(row, fields)
    end
  end

  defp with_rich_rows(field, _value, _key), do: field

  defp rich_row_fields(rows, struct, key) do
    if relation?(struct, key) and Enum.any?(rows, &match?(%__MODULE__{value: %_{}}, &1)),
      do: Brando.RichText.row_fields_for_printing(struct, key),
      else: []
  end

  defp relation?(struct, key) do
    function_exported?(struct, :__schema__, 1) and
      to_string(key) in Enum.map(struct.__schema__(:associations) ++ struct.__schema__(:embeds), &Atom.to_string/1)
  end

  defp put_rich(%__MODULE__{value: %_{}} = row, fields), do: %{row | rich: fields}
  defp put_rich(row, _fields), do: row

  defp named?([], _key), do: false
  defp named?(fields, key), do: to_string(key) in Enum.map(fields, &Atom.to_string/1)

  # `rendered_blocks`, and `rendered_<name>` for each other block field
  defp rendered_blocks?(%struct{}, key) do
    function_exported?(struct, :__blocks_fields__, 0) and
      to_string(key) in Enum.map(struct.__blocks_fields__(), &"rendered_#{&1.name}")
  end

  defp rich_text?(%TextBlock.Data{}, key), do: to_string(key) == "text"

  defp rich_text?(%Var{type: type}, key) when type in [:rich_text, :html], do: to_string(key) == "value"

  # A field the default form draws as rich text, or only named forms do
  defp rich_text?(%struct{}, key),
    do: to_string(key) in Enum.map(Brando.RichText.fields_for_printing(struct), &Atom.to_string/1)

  # Decoded first, as a heading is: a character reference typed into a title
  # (`&shy;`) is the character it names, and text escaped already stays as it is.
  defp escape(text) do
    if plain?(text), do: text, else: text |> HtmlEntities.decode() |> Parser.escape_var_value()
  end

  # Most text a template reads: no reading of it changes it
  defp plain?(<<char, _::binary>>) when char in ~c(<>&"'{}), do: false
  defp plain?(<<_, rest::binary>>), do: plain?(rest)
  defp plain?(<<>>), do: true

  defp hidden?(%User{}, key, _mode), do: key not in @user_keys
  defp hidden?(%_{}, key, _mode), do: credential?(key)
  defp hidden?(_value, _key, mode) when mode in [:processed, :names], do: false
  defp hidden?(_value, key, _mode), do: credential?(key)

  # `accessToken` from JSON is two words; most keys have no capital to look at
  defp credential?(key) when is_binary(key) do
    case String.downcase(key, :ascii) do
      ^key -> credential_word?(key)
      lower -> credential_word?(lower) or key |> Macro.underscore() |> credential_word?()
    end
  end

  defp credential?(key) when is_atom(key), do: credential?(Atom.to_string(key))
  defp credential?(_key), do: false

  # Read on every key: a walk over the name, not a pattern compiled per call. A
  # credential is a whole word of it, so `secretary` and `tokens` are no credentials.
  for word <- @credential_words do
    defp credential_word?(unquote(word)), do: true
    defp credential_word?(<<unquote(word), "_", _::binary>>), do: true
    defp credential_word?(<<unquote(word), "-", _::binary>>), do: true
  end

  defp credential_word?(name), do: next_word(name)

  defp next_word(<<char, rest::binary>>) when char in [?_, ?-], do: credential_word?(rest)
  defp next_word(<<_, rest::binary>>), do: next_word(rest)
  defp next_word(<<>>), do: false

  defp without_credentials(%User{} = user),
    do: User |> struct(Map.take(user, @user_fields)) |> Map.put(:__meta__, user.__meta__)

  defp without_credentials(%struct{} = value) when struct in @values, do: value

  defp without_credentials(%struct{} = value) do
    # A struct's fields do not change, and tags read many records of one schema
    fields =
      case Process.get({__MODULE__, struct}) do
        nil ->
          fields = value |> Map.keys() |> Enum.filter(&credential?/1)
          Process.put({__MODULE__, struct}, fields)
          fields

        fields ->
          fields
      end

    Enum.reduce(fields, value, &Map.put(&2, &1, nil))
  end

  defp without_credentials(%{} = value) do
    :maps.map(fn key, field -> if credential?(key), do: nil, else: field end, value)
  end

  defp without_credentials(value), do: value

  defimpl String.Chars do
    alias Brando.Villain.TemplateView

    # As Liquid prints a map, and nothing for a struct that has no text
    def to_string(%{value: value, mode: mode}) do
      cond do
        is_struct(value) and String.Chars.impl_for(value) ->
          value |> Kernel.to_string() |> TemplateView.wrap(mode)

        is_struct(value) ->
          ""

        true ->
          value
          |> TemplateView.printable()
          |> Liquex.Render.to_output_string()
          |> TemplateView.wrap(mode)
      end
    end
  end

  defimpl Liquex.Collection do
    alias Liquex.Collection

    def limit(view, limit), do: view |> items() |> Collection.limit(limit)
    def offset(view, offset), do: view |> items() |> Collection.offset(offset)
    def reverse(view), do: view |> items() |> Collection.reverse()
    def sort(view), do: view |> items() |> Collection.sort()
    def sort(view, field), do: view |> items() |> Collection.sort(field)
    def sort_case_insensitive(view), do: view |> items() |> Collection.sort_case_insensitive()
    def sort_case_insensitive(view, field), do: view |> items() |> Collection.sort_case_insensitive(field)
    def where(view, field), do: view |> items() |> Collection.where(field)
    def where(view, field, value), do: view |> items() |> Collection.where(field, value)
    def to_enumerable(view), do: items(view)

    defp items(%{value: %_{} = value}), do: raise(Protocol.UndefinedError, protocol: Liquex.Collection, value: value)
    defp items(view), do: Brando.Villain.TemplateView.pairs(view)
  end
end
