defmodule Brando.Globals do
  @moduledoc """
  Globals
  """
  alias Brando.Cache
  alias Brando.Sites.GlobalCategory
  alias Brando.Villain

  import Ecto.Query
  use Brando.Query

  @type changeset :: Ecto.Changeset.t()
  @type global_category :: Brando.Sites.GlobalCategory.t()
  @type params :: map

  query :list, GlobalCategory, do: fn query -> from(q in query) end

  filters GlobalCategory do
    fn
      {:language, language}, query ->
        from(q in query, where: q.language == ^language)

      {:key, key}, query ->
        from(q in query, where: ilike(q.key, ^"%#{key}%"))

      {:label, label}, query ->
        from(q in query, where: ilike(q.label, ^"%#{label}%"))
    end
  end

  query :single, GlobalCategory, do: fn query -> from(q in query) end

  matches GlobalCategory do
    fn
      {:id, id}, query -> from(t in query, where: t.id == ^id)
      {:key, key}, query -> from(t in query, where: t.key == ^key)
    end
  end

  mutation :create, GlobalCategory do
    fn entry ->
      {:ok, entry}
      |> Cache.Globals.update()
      |> update_villains_referencing_global()
    end
  end

  mutation :update, GlobalCategory do
    fn entry ->
      {:ok, entry}
      |> Cache.Globals.update()
      |> update_villains_referencing_global()
    end
  end

  mutation :delete, GlobalCategory

  @doc """
  Get global by category and key
  """
  def get_global(cat_key, key, globals) when is_map(globals) do
    case get_in(globals, [cat_key, key]) do
      nil -> {:error, {:global, :not_found}}
      val -> {:ok, val}
    end
  end

  @doc """
  Get global by key path
  """
  def get_global(key_path, globals) when is_map(globals) do
    case String.split(key_path, ".") do
      [cat_key, key] -> get_global(cat_key, key, globals)
      _ -> {:error, {:global, :not_found}}
    end
  end

  def get_global(cat_key, key) do
    case get_in(Cache.Globals.get(), [cat_key, key]) do
      nil -> {:error, {:global, :not_found}}
      val -> {:ok, val}
    end
  end

  def get_global(key_path) do
    case String.split(key_path, ".") do
      [cat_key, key] -> get_global(cat_key, key, Cache.Globals.get())
      _ -> {:error, {:global, :not_found}}
    end
  end

  @doc """
  Get global, return global or empty string
  """
  def get_global!(key_path) do
    case get_global(key_path) do
      {:ok, global} -> global
      _ -> ""
    end
  end

  def get_global!(key_path, globals) do
    case get_global(key_path, globals) do
      {:ok, global} -> global
      _ -> ""
    end
  end

  def get_global_value!(key_path) when is_binary(key_path) do
    get_global!(key_path)
    |> get_global_value!()
  end

  def get_global_value!(%{type: "boolean", data: %{"value" => ""}}), do: false
  def get_global_value!(%{type: "boolean", data: %{"value" => false}}), do: false
  def get_global_value!(%{type: "boolean", data: %{"value" => _}}), do: true

  def get_global_value!(%{type: "datetime", data: %{"value" => value}}) do
    {:ok, datetime, _} = DateTime.from_iso8601(value)
    datetime
  end

  @doc """
  Render global by key path
  """
  def render_global(key_path, globals \\ Cache.Globals.get()) do
    case get_global(key_path, globals) do
      {:ok, global} -> global
      _ -> ""
    end
  end

  @doc """
  Check all fields for references to GLOBAL
  Rerender if found.
  """
  @spec update_villains_referencing_global({:ok, global_category} | {:error, changeset}) ::
          {:ok, global_category} | {:error, changeset}
  def update_villains_referencing_global({:error, changeset}), do: {:error, changeset}

  def update_villains_referencing_global({:ok, global_category}) do
    search_terms = [globals: "{{ globals\.(.*?) }}"]

    villains = Villain.list_villains()
    Villain.rerender_matching_villains(villains, search_terms)
    Villain.rerender_matching_modules(villains, search_terms)

    {:ok, global_category}
  end
end
