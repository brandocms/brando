defmodule Brando.Villain.Parser do
  @moduledoc """
  Defines callbacks for the Villain.Parser behaviour.
  """

  @doc "Parses a header"
  @callback header(%{String.t() => any}) :: String.t()

  @doc "Parses text/paragraphs"
  @callback text(%{String.t() => any}) :: String.t()

  @doc "Parses video"
  @callback video(%{String.t() => any}) :: String.t()

  @doc "Parses map"
  @callback map(%{String.t() => any}) :: String.t()

  @doc "Parses image"
  @callback image(%{String.t() => any}) :: String.t()

  @doc "Parses slideshow"
  @callback slideshow(%{String.t() => any}) :: String.t()

  @doc "Parses divider"
  @callback divider(%{String.t() => any}) :: String.t()

  @doc "Parses list"
  @callback list(%{String.t() => any}) :: String.t()

  @doc "Parses blockquote"
  @callback blockquote(%{String.t() => any}) :: String.t()

  @doc "Parses columns"
  @callback columns(%{String.t() => any}) :: String.t()

  @doc "Parses datatables"
  @callback datatable(%{String.t() => any}) :: String.t()

  @doc "Parses markdown"
  @callback markdown(%{String.t() => any}) :: String.t()

  @doc "Parses html"
  @callback html(%{String.t() => any}) :: String.t()
end
