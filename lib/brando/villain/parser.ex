defmodule Brando.Villain.Parser do
  @moduledoc """
  Defines callbacks for the Villain.Parser behaviour.
  """

  use Behaviour

  @doc "Parses a header"
  defcallback header(%{String.t => any}) :: String.t

  @doc "Parses text/paragraphs"
  defcallback text(%{String.t => any}) :: String.t

  @doc "Parses video"
  defcallback video(%{String.t => any}) :: String.t

  @doc "Parses image"
  defcallback image(%{String.t => any}) :: String.t

  @doc "Parses slideshow"
  defcallback slideshow(%{String.t => any}) :: String.t

  @doc "Parses divider"
  defcallback divider(%{String.t => any}) :: String.t

  @doc "Parses list"
  defcallback list(%{String.t => any}) :: String.t

  @doc "Parses blockquote"
  defcallback blockquote(%{String.t => any}) :: String.t

  @doc "Parses columns"
  defcallback columns(%{String.t => any}) :: String.t
end
