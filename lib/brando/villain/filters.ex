defmodule Brando.Villain.Filters do
  use Phoenix.Component
  alias Brando.Content.Var
  alias Brando.Utils
  alias Liquex.Context

  @moduledoc """
  Contains all the basic filters for Liquid
  """

  @type filter_t :: {:filter, [...]}
  @callback apply(any, filter_t, map) :: any

  defmacro __using__(_) do
    quote do
      @behaviour Brando.Villain.Filters

      @spec apply(any, Brando.Villain.Filters.filter_t(), map) :: any
      @impl Brando.Villain.Filters
      def apply(value, filter, context),
        do: Brando.Villain.Filters.apply(__MODULE__, value, filter, context)
    end
  end

  @spec filter_name(filter_t) :: String.t()
  def filter_name({:filter, [filter_name | _]}), do: filter_name

  def apply(
        mod \\ __MODULE__,
        value,
        {:filter, [function, {:arguments, arguments}]},
        context
      ) do
    func = String.to_existing_atom(function)

    function_args =
      Enum.map(
        arguments,
        &Liquex.Argument.eval(&1, context)
      )
      |> merge_keywords()

    mod =
      if mod != __MODULE__ and Kernel.function_exported?(mod, func, length(function_args) + 2) do
        mod
      else
        __MODULE__
      end

    # require Logger

    # Logger.error("""

    # filters
    # mod: #{inspect(mod, pretty: true)}
    # func: #{inspect(func, pretty: true)}
    # value: #{inspect(value, pretty: true)}
    # function_args: #{inspect(function_args, pretty: true)}

    # """)

    Kernel.apply(mod, func, [value | function_args] ++ [context])
  rescue
    # credo:disable-for-next-line
    ArgumentError -> raise Liquex.Error, "Invalid filter #{function}"
  end

  # Merges the tuples at the end of the argument list into a keyword list, but with string keys
  #     value, size, {"crop", direction}, {"filter", filter}
  # becomes
  #     value, size, [{"crop", direction}, {"filter", filter}]
  defp merge_keywords(arguments) do
    {keywords, rest} =
      arguments
      |> Enum.reverse()
      |> Enum.split_while(&is_tuple/1)

    case keywords do
      [] -> rest
      _ -> [Enum.reverse(keywords) | rest]
    end
    |> Enum.reverse()
  end

  @doc """
  Returns the absolute value of `value`.

  ## Examples

      iex> Brando.Villain.Filters.abs(-1, %{})
      1

      iex> Brando.Villain.Filters.abs(1, %{})
      1

      iex> Brando.Villain.Filters.abs("-1.1", %{})
      1.1
  """
  @spec abs(String.t() | number, any) :: number
  def abs(value, _) when is_binary(value) do
    {float, ""} = Float.parse(value)
    abs(float)
  end

  def abs(value, _), do: abs(value)

  @doc """
  Appends `text` to the end of `value`

  ## Examples

      iex> Brando.Villain.Filters.append("myfile", ".html", %{})
      "myfile.html"
  """
  @spec append(String.t(), String.t(), map()) :: String.t()
  def append(value, text, _), do: to_string(value) <> to_string(text)

  @doc """
  Sets a minimum value

  ## Examples

      iex> Brando.Villain.Filters.at_least(3, 5, %{})
      5

      iex> Brando.Villain.Filters.at_least(5, 3, %{})
      5
  """
  @spec at_least(number, number, map()) :: number
  def at_least(value, min, _) when value > min, do: value
  def at_least(_value, min, _), do: min

  @doc """
  Sets a maximum value

  ## Examples

      iex> Brando.Villain.Filters.at_most(4, 5, %{})
      4

      iex> Brando.Villain.Filters.at_most(4, 3, %{})
      3
  """
  @spec at_most(number, number, map()) :: number
  def at_most(value, max, _) when value < max, do: value
  def at_most(_value, max, _), do: max

  @doc """
  Capitalizes a string

  ## Examples

      iex> Brando.Villain.Filters.capitalize("title", %{})
      "Title"

      iex> Brando.Villain.Filters.capitalize("my great title", %{})
      "My great title"
  """
  @spec capitalize(String.t(), map()) :: String.t()
  def capitalize(value, _), do: String.capitalize(to_string(value))

  @doc """
  Rounds `value` up to the nearest whole number. Liquid tries to convert the input to a number before the filter is applied.

  ## Examples

      iex> Brando.Villain.Filters.ceil(1.2, %{})
      2

      iex> Brando.Villain.Filters.ceil(2.0, %{})
      2

      iex> Brando.Villain.Filters.ceil(183.357, %{})
      184

      iex> Brando.Villain.Filters.ceil("3.5", %{})
      4
  """
  @spec ceil(number | String.t(), map()) :: number
  def ceil(value, _) when is_binary(value) do
    {num, ""} = Float.parse(value)
    Float.ceil(num) |> trunc()
  end

  def ceil(value, _), do: Float.ceil(value) |> trunc()

  @doc """
  Removes any nil values from an array.

  ## Examples

      iex> Brando.Villain.Filters.compact([1, 2, nil, 3], %{})
      [1,2,3]

      iex> Brando.Villain.Filters.compact([1, 2, 3], %{})
      [1,2,3]
  """
  @spec compact([any], map()) :: [any]
  def compact(value, _) when is_list(value),
    do: Enum.reject(value, &is_nil/1)

  @doc """
  Concatenates (joins together) multiple arrays. The resulting array contains all the items

  ## Examples

      iex> Brando.Villain.Filters.concat([1,2], [3,4], %{})
      [1,2,3,4]
  """
  def concat(value, other, _) when is_list(value) and is_list(other),
    do: value ++ other

  @doc """
  Allows you to specify a fallback in case a value doesn’t exist. default will show its value
  if the left side is nil, false, or empty.

  ## Examples

      iex> Brando.Villain.Filters.default("1.99", "2.99", %{})
      "1.99"

      iex> Brando.Villain.Filters.default("", "2.99", %{})
      "2.99"
  """
  def default(value, def_value, _) when value in [nil, "", false, []], do: def_value
  def default(value, _, _), do: value

  @doc """
  Divides a number by another number.

  ## Examples

  The result is rounded down to the nearest integer (that is, the floor) if the divisor is an integer.

      iex> Brando.Villain.Filters.divided_by(16, 4, %{})
      4

      iex> Brando.Villain.Filters.divided_by(5, 3, %{})
      1

      iex> Brando.Villain.Filters.divided_by(20, 7.0, %{})
      2.857142857142857
  """
  def divided_by(value, divisor, _) when is_integer(divisor), do: trunc(value / divisor)
  def divided_by(value, divisor, _), do: value / divisor

  @doc """
  Makes each character in a string lowercase. It has no effect on strings
  which are already all lowercase.

  ## Examples

      iex> Brando.Villain.Filters.downcase("Parker Moore", %{})
      "parker moore"

      iex> Brando.Villain.Filters.downcase("apple", %{})
      "apple"
  """
  def downcase(nil, _), do: nil
  def downcase(value, _), do: String.downcase(to_string(value))

  @doc """
  Escapes a string by replacing characters with escape sequences (so that the string can
  be used in a URL, for example). It doesn’t change strings that don’t have anything to
  escape.

  ## Examples

      iex> Brando.Villain.Filters.escape("Have you read 'James & the Giant Peach'?", %{})
      "Have you read &#39;James &amp; the Giant Peach&#39;?"

      iex> Brando.Villain.Filters.escape("Tetsuro Takara", %{})
      "Tetsuro Takara"
  """
  def escape(value, _),
    do: HtmlEntities.encode(to_string(value))

  @doc """
  Escapes a string by replacing characters with escape sequences (so that the string can
  be used in a URL, for example). It doesn’t change strings that don’t have anything to
  escape.

  ## Examples

      iex> Brando.Villain.Filters.escape_once("1 &lt; 2 &amp; 3", %{})
      "1 &lt; 2 &amp; 3"
  """
  def escape_once(value, _),
    do: to_string(value) |> HtmlEntities.decode() |> HtmlEntities.encode()

  @doc """
  Returns the first item of an array.

  ## Examples

      iex> Brando.Villain.Filters.first([1, 2, 3], %{})
      1

      iex> Brando.Villain.Filters.first([], %{})
      nil
  """
  def first([], _), do: nil
  def first([f | _], _), do: f

  @doc """
  Rounds the input down to the nearest whole number. Liquid tries to convert the input to a
  number before the filter is applied.

  ## Examples

      iex> Brando.Villain.Filters.floor(1.2, %{})
      1

      iex> Brando.Villain.Filters.floor(2.0, %{})
      2
  """
  def floor(value, _), do: Kernel.trunc(value)

  @doc """
  Combines the items in `values` into a single string using `joiner` as a separator.

  ## Examples

      iex> Brando.Villain.Filters.join(~w(John Paul George Ringo), " and ", %{})
      "John and Paul and George and Ringo"
  """
  def join(values, joiner, _), do: Enum.join(values, joiner)

  @doc """
  Returns the last item of `arr`.

  ## Examples

      iex> Brando.Villain.Filters.last([1, 2, 3], %{})
      3

      iex> Brando.Villain.Filters.first([], %{})
      nil
  """
  @spec last(list, Liquex.Context.t()) :: any
  def last(arr, context), do: arr |> Enum.reverse() |> first(context)

  @doc """
  Removes all whitespace (tabs, spaces, and newlines) from the left side of a string.
  It does not affect spaces between words.

  ## Examples

      iex> Brando.Villain.Filters.lstrip("          So much room for activities!          ", %{})
      "So much room for activities!          "
  """
  @spec lstrip(String.t(), Context.t()) :: String.t()
  def lstrip(value, _), do: to_string(value) |> String.trim_leading()

  @doc """
  Creates an array (`arr`) of values by extracting the values of a named property from another object (`key`).

  ## Examples

      iex> Brando.Villain.Filters.map([%{"a" => 1}, %{"a" => 2, "b" => 1}], "a", %{})
      [1, 2]
  """
  @spec map([any], term, Context.t()) :: [any]
  def map(arr, key, _), do: Enum.map(arr, &Liquex.Indifferent.get(&1, key, nil))

  @doc """
  Subtracts a number from another number.

  ## Examples

      iex> Brando.Villain.Filters.minus(4, 2, %{})
      2

      iex> Brando.Villain.Filters.minus(183.357, 12, %{})
      171.357
  """
  @spec minus(number, number, Context.t()) :: number
  def minus(left, right, _), do: left - right

  @doc """
  Returns the remainder of a division operation.

  ## Examples

      iex> Brando.Villain.Filters.modulo(3, 2, %{})
      1

      iex> Brando.Villain.Filters.modulo(183.357, 12, %{})
      3.357
  """
  @spec modulo(number, number, Context.t()) :: number
  def modulo(left, right, _) when is_float(left) or is_float(right),
    do: :math.fmod(left, right) |> Float.round(5)

  def modulo(left, right, _), do: rem(left, right)

  @doc """
  Replaces every newline (\n) in a string with an HTML line break (<br />).

  ## Examples

      iex> Brando.Villain.Filters.newline_to_br("\\nHello\\nthere\\n", %{})
      "<br />\\nHello<br />\\nthere<br />\\n"
  """
  @spec newline_to_br(String.t(), Context.t()) :: String.t()
  def newline_to_br(value, _), do: String.replace(to_string(value), "\n", "<br />\n")

  def nl2br(value, ctx), do: newline_to_br(value, ctx)

  @doc """
  Partition list into `size`

  ## Examples

      iex> Brando.Villain.Filters.partition(["a", "b", "c", "d", "e"], 3, %{})
      [["a", "b", "c"], ["d", "e"]]
  """
  def partition(arr, size, _ctx) when is_list(arr) do
    Enum.chunk_every(arr, size)
  end

  @doc """
  Adds a number to another number.

  ## Examples

      iex> Brando.Villain.Filters.plus(4, 2, %{})
      6

      iex> Brando.Villain.Filters.plus(183.357, 12, %{})
      195.357
  """
  def plus(left, right, _), do: left + right

  @doc """
  Adds the specified string to the beginning of another string.

  ## Examples

      iex> Brando.Villain.Filters.prepend("apples, oranges, and bananas", "Some fruit: ", %{})
      "Some fruit: apples, oranges, and bananas"

      iex> Brando.Villain.Filters.prepend("/index.html", "example.com", %{})
      "example.com/index.html"
  """
  def prepend(value, prepender, _), do: to_string(prepender) <> to_string(value)

  @doc """
  Removes every occurrence of the specified substring from a string.

  ## Examples

      iex> Brando.Villain.Filters.remove("I strained to see the train through the rain", "rain", %{})
      "I sted to see the t through the "
  """
  def remove(value, original, context), do: replace(value, original, "", context)

  @doc """
  Removes every occurrence of the specified substring from a string.

  ## Examples

      iex> Brando.Villain.Filters.remove_first("I strained to see the train through the rain", "rain", %{})
      "I sted to see the train through the rain"
  """
  def remove_first(value, original, context), do: replace_first(value, original, "", context)

  @doc """
  Replaces every occurrence of the first argument in a string with the second argument.

  ## Examples

      iex> Brando.Villain.Filters.replace("Take my protein pills and put my helmet on", "my", "your", %{})
      "Take your protein pills and put your helmet on"
  """
  def replace(value, original, replacement, _),
    do: String.replace(to_string(value), to_string(original), to_string(replacement))

  @doc """
  Replaces only the first occurrence of the first argument in a string with the second argument.

  ## Examples

      iex> Brando.Villain.Filters.replace_first("Take my protein pills and put my helmet on", "my", "your", %{})
      "Take your protein pills and put my helmet on"
  """
  def replace_first(value, original, replacement, _),
    do:
      String.replace(to_string(value), to_string(original), to_string(replacement), global: false)

  @doc """
  Reverses the order of the items in an array. reverse cannot reverse a string.

  ## Examples

      iex> Brando.Villain.Filters.reverse(~w(apples oranges peaches plums), %{})
      ["plums", "peaches", "oranges", "apples"]
  """
  def reverse(arr, _) when is_list(arr), do: Enum.reverse(arr)

  @doc """
  Rounds a number to the nearest integer or, if a number is passed as an argument, to that number of decimal places.

  ## Examples

      iex> Brando.Villain.Filters.round(1, %{})
      1

      iex> Brando.Villain.Filters.round(1.2, %{})
      1

      iex> Brando.Villain.Filters.round(2.7, %{})
      3

      iex> Brando.Villain.Filters.round(183.357, 2, %{})
      183.36
  """
  def round(value, precision \\ 0, context)
  def round(value, _, _) when is_integer(value), do: value
  def round(value, 0, _), do: value |> Float.round() |> trunc()
  def round(value, precision, _), do: Float.round(value, precision)

  @doc """
  Removes all whitespace (tabs, spaces, and newlines) from the right side of a string.
  It does not affect spaces between words.

  ## Examples

      iex> Brando.Villain.Filters.rstrip("          So much room for activities!          ", %{})
      "          So much room for activities!"
  """
  def rstrip(value, _), do: to_string(value) |> String.trim_trailing()

  @doc """
  Returns the number of characters in a string or the number of items in an array.

  ## Examples

      iex> Brando.Villain.Filters.size("Ground control to Major Tom.", %{})
      28

      iex> Brando.Villain.Filters.size(~w(apples oranges peaches plums), %{})
      4
  """
  def size(value, _) when is_list(value), do: length(value)
  def size(value, _), do: String.length(to_string(value))

  @doc """
  Returns a substring of 1 character beginning at the index specified by the
  first argument. An optional second argument specifies the length of the
  substring to be returned.

  ## Examples

      iex> Brando.Villain.Filters.slice("Liquid", 0, %{})
      "L"

      iex> Brando.Villain.Filters.slice("Liquid", 2, %{})
      "q"

      iex> Brando.Villain.Filters.slice("Liquid", 2, 5, %{})
      "quid"

  If the first argument is a negative number, the indices are counted from
  the end of the string:

  ## Examples

      iex> Brando.Villain.Filters.slice("Liquid", -3, 2, %{})
      "ui"
  """
  def slice(value, start, length \\ 1, _),
    do: String.slice(to_string(value), start, length)

  @doc """
  Sorts items in an array in case-sensitive order.

  ## Examples

      iex> Brando.Villain.Filters.sort(["zebra", "octopus", "giraffe", "Sally Snake"], %{})
      ["Sally Snake", "giraffe", "octopus", "zebra"]
  """
  def sort(list, _), do: Liquex.Collection.sort(list)
  def sort(list, field_name, _), do: Liquex.Collection.sort(list, field_name)

  @doc """
  Sorts items in an array in case-insensitive order.

  ## Examples

      iex> Brando.Villain.Filters.sort_natural(["zebra", "octopus", "giraffe", "Sally Snake"], %{})
      ["giraffe", "octopus", "Sally Snake", "zebra"]
  """
  def sort_natural(list, _), do: Liquex.Collection.sort_case_insensitive(list)

  def sort_natural(list, field_name, _),
    do: Liquex.Collection.sort_case_insensitive(list, field_name)

  @doc """
  Divides a string into an array using the argument as a separator. split is
  commonly used to convert comma-separated items from a string to an array.

  ## Examples

      iex> Brando.Villain.Filters.split("John, Paul, George, Ringo", ", ", %{})
      ["John", "Paul", "George", "Ringo"]
  """
  def split(value, separator, _), do: String.split(to_string(value), to_string(separator))

  @doc """
  Removes all whitespace (tabs, spaces, and newlines) from both the left and
  right side of a string. It does not affect spaces between words.

  ## Examples

      iex> Brando.Villain.Filters.strip("          So much room for activities!          ", %{})
      "So much room for activities!"
  """
  def strip(value, _), do: String.trim(to_string(value))

  @doc """
  Removes any HTML tags from a string.

  ## Examples

      iex> Brando.Villain.Filters.strip_html("Have <em>you</em> read <strong>Ulysses</strong>?", %{})
      "Have you read Ulysses?"
  """
  def strip_html(value, _), do: HtmlSanitizeEx.strip_tags(to_string(value))

  @doc """
  Removes any newline characters (line breaks) from a string.

  ## Examples

      iex> Brando.Villain.Filters.strip_newlines("Hello\\nthere", %{})
      "Hellothere"
  """
  def strip_newlines(value, _) do
    to_string(value)
    |> String.replace("\r", "")
    |> String.replace("\n", "")
  end

  @doc """
  Multiplies a number by another number.

  ## Examples

      iex> Brando.Villain.Filters.times(3, 4, %{})
      12

      iex> Brando.Villain.Filters.times(24, 7, %{})
      168

      iex> Brando.Villain.Filters.times(183.357, 12, %{})
      2200.284
  """
  def times(value, divisor, _), do: value * divisor

  @doc """
  Shortens a string down to the number of characters passed as an argument. If
  the specified number of characters is less than the length of the string, an
  ellipsis (…) is appended to the string and is included in the character
  count.

  ## Examples

      iex> Brando.Villain.Filters.truncate("Ground control to Major Tom.", 20, %{})
      "Ground control to..."

      iex> Brando.Villain.Filters.truncate("Ground control to Major Tom.", 25, ", and so on", %{})
      "Ground control, and so on"

      iex> Brando.Villain.Filters.truncate("Ground control to Major Tom.", 20, "", %{})
      "Ground control to Ma"
  """
  def truncate(value, length, ellipsis \\ "...", _) do
    value = to_string(value)

    if String.length(value) <= length do
      value
    else
      String.slice(
        value,
        0,
        length - String.length(ellipsis)
      ) <> ellipsis
    end
  end

  @doc """
  Shortens a string down to the number of characters passed as an argument. If
  the specified number of characters is less than the length of the string, an
  ellipsis (…) is appended to the string and is included in the character
  count.

  ## Examples

      iex> Brando.Villain.Filters.truncatewords("Ground control to Major Tom.", 3, %{})
      "Ground control to..."

      iex> Brando.Villain.Filters.truncatewords("Ground control to Major Tom.", 3, "--", %{})
      "Ground control to--"

      iex> Brando.Villain.Filters.truncatewords("Ground control to Major Tom.", 3, "", %{})
      "Ground control to"
  """
  def truncatewords(value, length, ellipsis \\ "...", _) do
    value = to_string(value)
    words = value |> String.split()

    if length(words) <= length do
      value
    else
      sentence =
        words
        |> Enum.take(length)
        |> Enum.join(" ")

      sentence <> ellipsis
    end
  end

  @doc """
  Removes any duplicate elements in an array.

  ## Examples

      iex> Brando.Villain.Filters.uniq(~w(ants bugs bees bugs ants), %{})
      ["ants", "bugs", "bees"]
  """
  def uniq(list, _), do: Enum.uniq(list)

  @doc """
  Makes each character in a string uppercase. It has no effect on strings
  which are already all uppercase.

  ## Examples

      iex> Brando.Villain.Filters.upcase("Parker Moore", %{})
      "PARKER MOORE"

      iex> Brando.Villain.Filters.upcase("APPLE", %{})
      "APPLE"
  """
  def upcase(value, _), do: String.upcase(to_string(value))

  @doc """
  Decodes a string that has been encoded as a URL or by url_encode/2.

  ## Examples

      iex> Brando.Villain.Filters.url_decode("%27Stop%21%27+said+Fred", %{})
      "'Stop!' said Fred"
  """
  def url_decode(value, _), do: URI.decode_www_form(to_string(value))

  @doc """
  Decodes a string that has been encoded as a URL or by url_encode/2.

  ## Examples

      iex> Brando.Villain.Filters.url_encode("john@liquid.com", %{})
      "john%40liquid.com"

      iex> Brando.Villain.Filters.url_encode("Tetsuro Takara", %{})
      "Tetsuro+Takara"
  """
  def url_encode(value, _), do: URI.encode_www_form(to_string(value))

  @doc """
  Base encode 64 string without padding

  ## Examples

      iex> Brando.Villain.Filters.base_encode64(~s(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 93 107"><path d='M74,74a42,42 0,1,0-57,0l28,29a42,41 0,0,0 0-57' fill='#00a3dc' fill-rule='evenodd'/></svg>), %{})
      "PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCA5MyAxMDciPjxwYXRoIGQ9J003NCw3NGE0Miw0MiAwLDEsMC01NywwbDI4LDI5YTQyLDQxIDAsMCwwIDAtNTcnIGZpbGw9JyMwMGEzZGMnIGZpbGwtcnVsZT0nZXZlbm9kZCcvPjwvc3ZnPg"
  """
  def base_encode64(value, _), do: Base.encode64(value, padding: false)

  @doc """
  Creates an array including only the objects with a given property value, or
  any truthy value by default.

  ## Examples

      iex> Brando.Villain.Filters.where([%{"b" => 2}, %{"b" => 1}], "b", 1, %{})
      [%{"b" => 1}]
  """
  def where(list, key, value, _), do: Liquex.Collection.where(list, key, value)

  @doc """
  Creates an array including only the objects with a given truthy property value

  ## Examples

      iex> Brando.Villain.Filters.where([%{"b" => true, "value" => 1}, %{"b" => 1, "value" => 2}, %{"b" => false, "value" => 3}], "b", %{})
      [%{"b" => true, "value" => 1}, %{"b" => 1, "value" => 2}]
  """
  def where(list, key, _), do: Liquex.Collection.where(list, key)

  def zero_pad(number, length \\ 3, _) do
    Brando.HTML.zero_pad(number, length)
  end

  @doc """
  Converts `value` timestamp into another date `format`.
  The format for this syntax is the same as strftime. The input uses the same format as Ruby’s Time.parse.
  ## Examples
      iex> Brando.Villain.Filters.date(~D[2000-01-01], "%m/%d/%Y", %{})
      "01/01/2000"
      iex> Brando.Villain.Filters.date(~N[2020-07-06 15:00:00.000000], "%m/%d/%Y", %{})
      "07/06/2020"
      iex> Brando.Villain.Filters.date(~U[2020-07-06 15:00:00.000000Z], "%m/%d/%Y", %{})
      "07/06/2020"
  """

  def date(%Date{} = value, format, _) do
    value
    |> Utils.Datetime.format_datetime(format, nil)
  end

  def date(%DateTime{} = value, format, _) do
    value
    |> DateTime.shift_zone!(Brando.timezone())
    |> Utils.Datetime.format_datetime(format, nil)
  end

  def date(%NaiveDateTime{} = value, format, _),
    do: Utils.Datetime.format_datetime(value, format, nil)

  def date("now", format, context), do: date(DateTime.utc_now(), format, context)
  def date("today", format, context), do: date(Date.utc_today(), format, context)

  def date(value, format, _) when is_binary(value) do
    value
    |> DateTime.from_iso8601()
    |> Utils.Datetime.format_datetime(format, nil)
  end

  # {{ entry.inserted_at | date:"%-d. %B %Y","no" }}
  # = 4. januar 2022
  def date(%DateTime{} = value, format, locale, _) do
    Utils.Datetime.format_datetime(value, format, locale)
  end

  def date(value, format, locale, _) do
    Utils.Datetime.format_datetime(value, format, locale)
  end

  def inspect(value, _), do: "#{Kernel.inspect(value, pretty: true)}"

  def rows(%{data: %{data: %{rows: rows}}}, _) do
    rows
  end

  def rows(data, _) do
    IO.warn("""

    ERROR: The `rows` filter can only be used on a legacy table struct.

    Got:
    #{Kernel.inspect(data, pretty: true)}

    Try {{ block.table_rows }} instead.

    """)

    []
  end

  def humanize(value, _), do: Brando.Utils.humanize(value)

  @doc """
  Get key from image.

  It is prefered to use |size:"thumb" instead of this, but keeping these for backwards
  compatibility

  TODO: Remove before 1.0
  """
  @deprecated "Use `|size:\"large\"` instead"
  def large(%Brando.Images.Image{} = img, _) do
    assigns = %{
      src: img,
      opts: [
        key: :large,
        prefix: Brando.Utils.media_url()
      ]
    }

    ~H"""
    <Brando.HTML.picture src={@src} opts={@opts} />
    """
    |> Phoenix.LiveViewTest.rendered_to_string()
  end

  @deprecated "Use `|size:\"large\"` instead"
  def large(img, _) do
    assigns = %{
      src: img,
      opts: [
        key: :large
      ]
    }

    ~H"""
    <Brando.HTML.picture src={@src} opts={@opts} />
    """
    |> Phoenix.LiveViewTest.rendered_to_string()
  end

  @deprecated "Use `|size:\"xlarge\"` instead"
  def xlarge(%Brando.Images.Image{} = img, _) do
    assigns = %{
      src: img,
      opts: [
        key: :xlarge,
        prefix: Brando.Utils.media_url()
      ]
    }

    ~H"""
    <Brando.HTML.picture src={@src} opts={@opts} />
    """
    |> Phoenix.LiveViewTest.rendered_to_string()
  end

  @deprecated "Use `|size:\"xlarge\"` instead"
  def xlarge(img, _) do
    assigns = %{
      src: img,
      opts: [
        key: :xlarge
      ]
    }

    ~H"""
    <Brando.HTML.picture src={@src} opts={@opts} />
    """
    |> Phoenix.LiveViewTest.rendered_to_string()
  end

  @doc """
  Get sized version of image
  """
  def size(%Brando.Images.Image{} = img, size, _) do
    assigns = %{
      src: img,
      opts: [
        key: size,
        prefix: Brando.Utils.media_url()
      ]
    }

    ~H"""
    <Brando.HTML.picture src={@src} opts={@opts} />
    """
    |> Phoenix.LiveViewTest.rendered_to_string()
  end

  def size(img, size, _) do
    assigns = %{
      src: img,
      opts: [
        key: size
      ]
    }

    ~H"""
    <Brando.HTML.picture src={@src} opts={@opts} />
    """
    |> Phoenix.LiveViewTest.rendered_to_string()
  end

  @doc """
  Get srcset picture of image

      {{ entry.cover|srcset:"Attivo.Team.Employee:cover" }}
      {{ entry.cover|srcset:"Attivo.Team.Employee:cover.listing_crop" }}

  """
  def srcset(%struct_type{} = img, srcset, _)
      when struct_type in [Brando.Images.Image] do
    assigns = %{
      src: img,
      opts: [
        placeholder: :svg,
        lazyload: true,
        srcset: srcset,
        prefix: Brando.Utils.media_url(),
        cache: img.updated_at
      ]
    }

    ~H"""
    <Brando.HTML.picture src={@src} opts={@opts} />
    """
    |> Phoenix.LiveViewTest.rendered_to_string()
  end

  def srcset(img, srcset, _) do
    assigns = %{
      src: img,
      opts: [
        placeholder: :svg,
        lazyload: true,
        srcset: srcset
      ]
    }

    ~H"""
    <Brando.HTML.picture src={@src} opts={@opts} />
    """
    |> Phoenix.LiveViewTest.rendered_to_string()
  end

  def filesize(size, _) do
    Brando.Utils.human_size(size)
  end

  @doc """
  Get entry publication date by publish_at OR inserted_at
  """
  def publish_date(%{publish_at: publish_at}, format, locale, _)
      when not is_nil(publish_at) do
    Utils.Datetime.format_datetime(publish_at, format, locale)
  end

  def publish_date(%{inserted_at: inserted_at}, format, locale, _) do
    Utils.Datetime.format_datetime(inserted_at, format, locale)
  end

  @doc """
  Attempt to get `entry`'s absolute URL through blueprint
  """
  def absolute_url(%{__struct__: schema} = entry, _) do
    schema.__absolute_url__(entry)
  end

  @doc """
  Prefix media url to file/image
  """
  def media_url(%Brando.Files.File{} = file, _) do
    Utils.media_url(file)
  end

  def media_url(%Brando.Images.Image{} = img, _) do
    Brando.Utils.img_url(img, :original, prefix: Brando.Utils.media_url())
  end

  def media_url(%Ecto.Association.NotLoaded{}, _) do
    require Logger

    Logger.error("""

    Tried calling the `media_url` filter on a not loaded association.
    If you are using datasources, make sure you have preloaded the assoications you are trying to access in the template

    """)

    ""
  end

  def media_url(nil, _) do
    ""
  end

  def schema(%{__struct__: schema}, _) do
    to_string(schema)
  end

  def schema(_, _) do
    nil
  end

  def renderless(_, _) do
    ""
  end

  @doc """
  Get src of image
  """
  def src(%Brando.Images.Image{} = img, size, _) do
    Brando.Utils.img_url(img, size, prefix: Brando.Utils.media_url())
  end

  def src(img, size, _) do
    Brando.Utils.img_url(img, size)
  end

  def orientation(value, _), do: Brando.Images.get_image_orientation(value)

  @doc """
  Converts from markdown
  ## Examples
      iex> Brando.Villain.Filters.markdown("this is a **string**", %{}) |> String.trim("\\n")
      "<p>\\nthis is a <strong>string</strong></p>"
  """
  def markdown(%{value: str}, opts), do: markdown(str, opts)

  def markdown(str, _) when is_binary(str) do
    str
    |> Brando.HTML.render_markdown()
    |> Phoenix.HTML.safe_to_string()
  end

  @doc """
  Checks if `url` matches the current entry's `url`
  """
  def active(url, ctx) do
    if absolute_url = Map.get(ctx.variables, "url") do
      url = (String.starts_with?(url, "/") && url) || "/#{url}"
      (url == absolute_url && "active") || ""
    else
      ""
    end
  end

  def slugify(nil, _) do
    ""
  end

  def slugify(str, _) when is_binary(str) do
    Brando.Utils.slugify(str)
  end

  def link_url(%Var{type: :link} = var, _ctx) do
    get_link_url(var) || nil
  end

  def link_text(%Var{type: :link} = var, _ctx) do
    get_link_text(var) || nil
  end

  defp get_link_url(%{link_type: :url, value: url}), do: url
  defp get_link_url(%{link_type: :identifier, identifier: %{url: url}}), do: url
  defp get_link_url(_), do: nil

  defp get_link_text(%{link_type: :url, link_text: text}), do: text

  defp get_link_text(%{link_type: :identifier, link_text: text})
       when not is_nil(text),
       do: text

  defp get_link_text(%{link_type: :identifier, link_text: nil, identifier: %{title: text}}),
    do: text

  defp get_link_text(_), do: nil
end
