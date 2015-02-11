defmodule Villain.Parser do
  use Behaviour

  @doc "Parses a header"
  defcallback header(String.t) :: String.t

  @doc "Parses text/paragraphs"
  defcallback text(String.t) :: String.t
end