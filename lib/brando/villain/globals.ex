defmodule Brando.Villain.Globals do
  @moduledoc """
  Replacing globals in data fields
  """

  alias Brando.Sites

  @regex_global_ref ~r/(?:\$\{|\$\%7B)GLOBAL:([a-zA-Z0-9-_.]+)(?:\}|\%7D)/i

  @doc """
  Replace global refs in `html`
  """
  def replace_global_refs(html) do
    {:ok, global_categories} = Sites.get_global_categories()

    Regex.replace(@regex_global_ref, html, fn _, key ->
      case Sites.find_global(global_categories, key) do
        {:ok, global} ->
          Phoenix.HTML.Safe.to_iodata(global)

        {:error, {:global, :not_found}} ->
          key
      end
    end)
  end
end
