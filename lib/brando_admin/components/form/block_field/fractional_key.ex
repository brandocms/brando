defmodule BrandoAdmin.Components.Form.BlockField.FractionalKey do
  @moduledoc """
  Fractional keys for block order in the edit session.

  A key is a string of base-62 digits that sorts lexicographically. There is
  always a key between two others, so an insert names its place by the keys
  of the neighbours it was put between, not by an index. Two editors who put
  a block in the same place at the same time get the same key; the tie is
  broken by uid, and both blocks stay. With indexes, the second insert would
  land one place off whenever the first had shifted the list.

  Keys live only in the session's state (`BlockField.Ops`). Saving still
  writes the integer `sequence` from list order, so the database needs no
  new column.

  The midpoint is David Greenspan's algorithm ("Implementing Fractional
  Indexing", the same as Figma's). A key never ends in the lowest digit, so
  there is always room before it.
  """

  @digits ~c"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
  @base length(@digits)
  @index Map.new(Enum.with_index(@digits))

  @type t :: String.t()

  @doc """
  A key strictly between `a` and `b`. `nil` stands for the start (as `a`) or
  the end (as `b`).

  ## Examples

      iex> alias BrandoAdmin.Components.Form.BlockField.FractionalKey
      iex> FractionalKey.between(nil, nil)
      "V"
      iex> a = FractionalKey.between(nil, nil)
      iex> b = FractionalKey.between(a, nil)
      iex> c = FractionalKey.between(a, b)
      iex> a < c and c < b
      true

  """
  @spec between(t() | nil, t() | nil) :: t()
  def between(a, b) when is_binary(a) and is_binary(b) and a >= b,
    do: raise(ArgumentError, "#{inspect(a)} is not before #{inspect(b)}")

  def between(a, b), do: a |> charlist() |> midpoint(b && String.to_charlist(b)) |> to_string()

  defp charlist(nil), do: []
  defp charlist(key), do: String.to_charlist(key)

  defp midpoint(a, b) when is_list(b) do
    case common_prefix(a, b) do
      0 ->
        midpoint_digit(a, b)

      n ->
        {prefix, b_rest} = Enum.split(b, n)
        prefix ++ midpoint(Enum.drop(a, n), b_rest)
    end
  end

  defp midpoint(a, nil), do: midpoint_digit(a, nil)

  # The length of the prefix `a` (padded with the lowest digit) shares with `b`.
  defp common_prefix(a, b), do: common_prefix(a, b, 0)
  defp common_prefix(_a, [], n), do: n

  defp common_prefix(a, [b | b_rest], n) do
    {a_digit, a_rest} = pop(a)
    if a_digit == b, do: common_prefix(a_rest, b_rest, n + 1), else: n
  end

  defp pop([]), do: {?0, []}
  defp pop([digit | rest]), do: {digit, rest}

  defp midpoint_digit(a, b) do
    digit_a = if a == [], do: 0, else: @index[hd(a)]
    digit_b = if b == nil, do: @base, else: @index[hd(b)]

    cond do
      digit_b - digit_a > 1 -> [Enum.at(@digits, round((digit_a + digit_b) / 2))]
      b != nil and length(b) > 1 -> [hd(b)]
      true -> [Enum.at(@digits, digit_a) | midpoint(Enum.drop(a, 1), nil)]
    end
  end

  @doc """
  `n` keys in order, spread evenly so later inserts anywhere stay short.

  ## Examples

      iex> alias BrandoAdmin.Components.Form.BlockField.FractionalKey
      iex> keys = FractionalKey.spread(3)
      iex> keys == Enum.sort(keys) and length(Enum.uniq(keys)) == 3
      true

  """
  @spec spread(non_neg_integer()) :: [t()]
  def spread(0), do: []

  def spread(n) do
    width = width(n + 1, 1)
    space = Integer.pow(@base, width)

    for i <- 1..n do
      (i * space)
      |> div(n + 1)
      |> encode(width)
      |> String.trim_trailing("0")
    end
  end

  defp width(count, width) do
    if Integer.pow(@base, width) >= count, do: width + 1, else: width(count, width + 1)
  end

  defp encode(value, width) do
    value
    |> Integer.digits(@base)
    |> Enum.map(&Enum.at(@digits, &1))
    |> to_string()
    |> String.pad_leading(width, "0")
  end

  @doc """
  Keys for `uids` in this order: each keeps the key it has in `keys` while
  that key still sorts after the one before it, and gets a new key between
  its neighbours otherwise. Returns `keys` with those of `uids` updated.
  """
  @spec rekey([String.t()], %{optional(String.t()) => t()}) :: %{optional(String.t()) => t()}
  def rekey(uids, keys) do
    {keys, _previous} =
      uids
      |> Enum.with_index()
      |> Enum.reduce({keys, nil}, fn {uid, index}, {keys, previous} ->
        key =
          case Map.get(keys, uid) do
            key when is_binary(key) and (is_nil(previous) or key > previous) ->
              key

            _ ->
              between(previous, next_kept(uids, index + 1, keys, previous))
          end

        {Map.put(keys, uid, key), key}
      end)

    keys
  end

  # The first key after `index` that will be kept: the bound a new key must
  # stay below.
  defp next_kept(uids, index, keys, previous) do
    uids
    |> Enum.drop(index)
    |> Enum.find_value(fn uid ->
      key = Map.get(keys, uid)
      if is_binary(key) and (is_nil(previous) or key > previous), do: key
    end)
  end
end
