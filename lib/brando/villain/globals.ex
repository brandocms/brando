defmodule Brando.Villain.Globals do
  @moduledoc """
  Replacing globals in data fields
  """

  alias Brando.Globals

  @regex_global_ref ~r/(?:\$\{|\$\%7B)GLOBAL:([a-zA-Z0-9-_.]+)(?:\}|\%7D)/i

  @doc """
  Replace global refs in `html`
  """
  def replace_global_refs(html) do
    Regex.replace(@regex_global_ref, html, fn _, key_path ->
      case Globals.get_global(key_path) do
        {:ok, global} ->
          Phoenix.HTML.Safe.to_iodata(global)

        {:error, {:global, :not_found}} ->
          key_path
      end
    end)
  end
end
