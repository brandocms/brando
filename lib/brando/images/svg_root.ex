defmodule Brando.Images.SvgRoot do
  @moduledoc """
  Reads an SVG's root element from the start of the file, without an XML parser.

  xmerl makes a permanent atom of every element and attribute name it meets, so
  an uploaded file could fill the VM's atom table. This looks at the first
  64 KB only, keeps attribute names and values as strings, and fetches nothing
  a DOCTYPE names.

  XML puts a DOCTYPE before the root element, so the prolog read here is the
  only place a file can declare entities: those are refused, as is a file whose
  root element is not `svg`, or does not start within those bytes.
  """

  @scan_bytes 65_536
  @attributes ~w(width height viewBox)
  @name_ends [" ", "\t", "\n", "\r", "=", "/", ">"]

  @type attributes :: %{optional(String.t()) => String.t()}

  @doc "How much of a file `parse/1` reads."
  @spec scan_bytes() :: pos_integer()
  def scan_bytes, do: @scan_bytes

  @doc """
  The root element's `width`, `height` and `viewBox`, from a file's contents.
  Only the first `scan_bytes/0` bytes are looked at. A root element that is cut
  off or malformed gives the attributes read so far.
  """
  @spec parse(binary) :: {:ok, attributes} | {:error, :not_svg | :entities}
  def parse(data) when is_binary(data) do
    data
    |> binary_part(0, min(byte_size(data), @scan_bytes))
    |> to_utf8()
    |> prolog()
  end

  defp to_utf8(<<0xEF, 0xBB, 0xBF, rest::binary>>), do: rest
  defp to_utf8(<<0xFF, 0xFE, rest::binary>>), do: from_utf16(rest, :little)
  defp to_utf8(<<0xFE, 0xFF, rest::binary>>), do: from_utf16(rest, :big)
  defp to_utf8(data), do: data

  # The scan can cut a character in two, and what follows it is not needed
  defp from_utf16(data, endian) do
    case :unicode.characters_to_binary(data, {:utf16, endian}, :utf8) do
      converted when is_binary(converted) -> converted
      {_incomplete_or_error, converted, _rest} -> converted
    end
  end

  defp prolog(<<c, rest::binary>>) when c in [?\s, ?\t, ?\n, ?\r], do: prolog(rest)
  defp prolog("<?" <> rest), do: rest |> after_marker("?>") |> prolog()
  defp prolog("<!--" <> rest), do: rest |> after_marker("-->") |> prolog()
  defp prolog("<!DOCTYPE" <> rest), do: doctype(rest)
  defp prolog("<" <> rest), do: root(rest)
  defp prolog(_data), do: {:error, :not_svg}

  defp after_marker(data, marker) do
    case :binary.split(data, marker) do
      [_before, rest] -> rest
      [_no_marker] -> ""
    end
  end

  defp doctype(">" <> rest), do: prolog(rest)
  defp doctype("[" <> rest), do: internal_subset(rest)
  defp doctype(<<quote, rest::binary>>) when quote in [?", ?'], do: rest |> after_marker(<<quote>>) |> doctype()
  defp doctype(<<_c, rest::binary>>), do: doctype(rest)
  defp doctype(""), do: {:error, :not_svg}

  defp internal_subset("<!ENTITY" <> _rest), do: {:error, :entities}
  defp internal_subset("<!--" <> rest), do: rest |> after_marker("-->") |> internal_subset()
  defp internal_subset("<?" <> rest), do: rest |> after_marker("?>") |> internal_subset()
  defp internal_subset("]" <> rest), do: doctype(rest)

  defp internal_subset(<<quote, rest::binary>>) when quote in [?", ?'],
    do: rest |> after_marker(<<quote>>) |> internal_subset()

  defp internal_subset(<<_c, rest::binary>>), do: internal_subset(rest)
  defp internal_subset(""), do: {:error, :not_svg}

  defp root(data) do
    {name, rest} = take_name(data)

    if name == "svg" or String.ends_with?(name, ":svg"),
      do: {:ok, attributes(rest, %{})},
      else: {:error, :not_svg}
  end

  defp attributes(data, found) do
    with {name, rest} when name != "" <- data |> skip_space() |> take_name(),
         "=" <> rest <- skip_space(rest),
         <<quote, rest::binary>> when quote in [?", ?'] <- skip_space(rest),
         [value, rest] <- :binary.split(rest, <<quote>>) do
      attributes(rest, if(name in @attributes, do: Map.put_new(found, name, value), else: found))
    else
      _end_of_tag -> found
    end
  end

  defp take_name(data) do
    case :binary.match(data, @name_ends) do
      {at, _length} -> {binary_part(data, 0, at), binary_part(data, at, byte_size(data) - at)}
      :nomatch -> {data, ""}
    end
  end

  defp skip_space(<<c, rest::binary>>) when c in [?\s, ?\t, ?\n, ?\r], do: skip_space(rest)
  defp skip_space(data), do: data
end
