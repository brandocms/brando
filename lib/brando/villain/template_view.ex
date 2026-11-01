defmodule Brando.Villain.TemplateView do
  @moduledoc """
  What a Liquid template reads of data it did not write: an entry and its
  preloads, `identity`, `navigation`, `request`, ref data and a datasource's
  `entries`.

  It prints the way a `string` var does. A string is HTML-escaped when it is
  read, with its braces as character references, so markup or Liquid in a
  field is printed as text. A field declared as rich text
  (`__rich_text_fields__`, a text ref's `text`, a placement's caption) arrives
  sanitized, to print as markup. A template opts in to a plain field's markup
  with the `raw` filter (`Brando.Villain.Filters.raw/2`).

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

  defstruct [:value, mode: :escape]

  @type mode :: :escape | :processed | :raw | :names
  @type t :: %__MODULE__{value: map(), mode: mode()}

  # In the context's private data, where no template can read or set it
  @raw_flag :brando_template_view_raw

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

  def fetch(%__MODULE__{value: value, mode: mode}, key, %Context{} = context) do
    with false <- hidden?(value, key, mode),
         {:ok, field} <- Liquex.Indifferent.fetch(value, key) do
      {:ok, read(value, key, field, read_mode(mode, context))}
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
  It goes back in a view of that mode, and a record it returned goes in one
  whatever it read. Text stays as a filter that makes markup or returns
  `{:safe, html}` gave it, and text from any filter starts no Liquid in the
  final pass, except in a Markdown template, which has none.
  """
  @spec filter_result(term(), atom(), mode() | nil, Context.t()) :: term()
  def filter_result({:safe, html}, _filter, _mode, context), do: html |> IO.iodata_to_binary() |> inert(context)

  def filter_result(result, filter, _mode, context) when is_binary(result) and filter in @filters_giving_markup,
    do: inert(result, context)

  def filter_result(result, _filter, nil, context), do: result |> wrap_records(context) |> inert(context)
  def filter_result(result, _filter, mode, context), do: result |> wrap(read_mode(mode, context)) |> inert(context)

  defp wrap_records(%_{} = record, context), do: wrap_for(record, context)
  defp wrap_records(value, context) when is_list(value), do: Enum.map(value, &wrap_records(&1, context))
  defp wrap_records(value, _context), do: value

  defp inert(value, context) when is_list(value), do: Enum.map(value, &inert(&1, context))

  defp inert(text, context) when is_binary(text) do
    if Markdown.template_context?(context), do: text, else: InertLiquid.encode_delimiters(text)
  end

  defp inert(value, _context), do: value

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
      [wrap(key, key_mode), wrap(field, field_mode)]
    end
  end

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

  defp read(value, key, field, :escape) when is_binary(field), do: read_text(value, key, field)
  defp read(_value, _key, field, mode), do: wrap(field, mode)

  defp read_text(%struct{} = value, key, text) do
    cond do
      plain?(text) -> text
      struct in @captioned and to_string(key) in ["title", "caption"] -> Captions.caption_html(text)
      rich_text?(value, key) -> text |> Brando.RichText.render_html() |> InertLiquid.encode_all()
      true -> escape(text)
    end
  end

  defp read_text(_value, _key, text), do: escape(text)

  defp rich_text?(%TextBlock.Data{}, key), do: to_string(key) == "text"

  defp rich_text?(%Var{type: type}, key) when type in [:rich_text, :html], do: to_string(key) == "value"

  defp rich_text?(%struct{}, key) do
    function_exported?(struct, :__rich_text_fields__, 0) and
      to_string(key) in Enum.map(struct.__rich_text_fields__(), &to_string/1)
  end

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
