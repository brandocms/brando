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
      case find_global(global_categories, key) do
        {:ok, global} ->
          Phoenix.HTML.Safe.to_iodata(global)

        {:error, {:global, :not_found}} ->
          key
      end
    end)
  end

  defp find_global(globals, key) do
    with {:ok, category_key, key} <- split_globals_path(key),
         {:ok, category} <- find_global_category(globals, category_key),
         {:ok, global} <- find_global_key(category, key) do
      {:ok, global}
    else
      {:error, {:global_key, :not_found}} ->
        "==> MISSING GLOBAL KEY: #{key} <=="
        {:error, {:global, :not_found}}

      {:error, {:global_category, :not_found}} ->
        "==> MISSING GLOBAL CATEGORY: #{key} <=="
        {:error, {:global, :not_found}}

      {:error, :split_globals} ->
        require Logger

        Logger.error(
          "==> replace_global_refs: Global key path without a category is deprecated. Try `${GLOBAL:system.#{
            key
          }}` instead"
        )

        {:error, {:global, :not_found}}
    end
  end

  defp split_globals_path(key) do
    key
    |> String.downcase()
    |> String.split(".")
    |> case do
      [category_key, key] ->
        {:ok, category_key, key}

      [_] ->
        {:error, :split_globals}
    end
  end

  defp find_global_category(global_categories, category_key) do
    case Enum.find(global_categories, &(String.downcase(&1.key) == String.downcase(category_key))) do
      nil -> {:error, {:global_category, :not_found}}
      category -> {:ok, category}
    end
  end

  defp find_global_key(category, key) do
    case Enum.find(category.globals, &(String.downcase(&1.key) == String.downcase(key))) do
      nil -> {:error, {:global_key, :not_found}}
      global -> {:ok, global}
    end
  end
end
