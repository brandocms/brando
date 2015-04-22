defmodule Villain.Parser do
  @moduledoc """
  Defines callbacks for the Villain.Parser behaviour.
  """
  use Behaviour

  @doc "Parses a header"
  defcallback header(String.t) :: String.t

  @doc "Parses text/paragraphs"
  defcallback text(String.t) :: String.t

  @doc "Parses video"
  defcallback video(String.t) :: String.t

  @doc "Parses image"
  defcallback image(String.t) :: String.t

  @doc "Parses divider"
  defcallback divider(String.t) :: String.t

  @doc "Parses list"
  defcallback list(String.t) :: String.t

  @doc "Parses columns"
  defcallback columns(String.t) :: String.t
end