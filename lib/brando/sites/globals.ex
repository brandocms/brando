defmodule Brando.Globals do
  @moduledoc """
  Globals
  """
  alias Brando.Cache
  alias Brando.Sites.Global
  alias Brando.Sites.GlobalCategory
  alias Brando.Villain

  import Ecto.Query
  use Brando.Query

  @type changeset :: Ecto.Changeset.t()
  @type global_category :: Brando.Sites.GlobalCategory.t()
  @type params :: map

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

  def get_global_value!(%Global{type: "boolean", data: %{"value" => ""}}), do: false
  def get_global_value!(%Global{type: "boolean", data: %{"value" => false}}), do: false
  def get_global_value!(%Global{type: "boolean", data: %{"value" => _}}), do: true

  def get_global_value!(%Global{type: "datetime", data: %{"value" => value}}) do
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
  List global categories, without preload
  """
  def list_global_categories do
    {:ok, Brando.repo().all(GlobalCategory)}
  end

  @doc """
  Get global categories, preloaded with globals
  """
  def get_global_categories do
    query = from t in GlobalCategory, preload: :globals
    {:ok, Brando.repo().all(query)}
  end

  @doc """
  Get global category
  """
  @spec get_global_category(category_id :: any) ::
          {:ok, global_category()} | {:error, {:global_category, :not_found}}
  def get_global_category(category_id) do
    case Brando.repo().get_by(GlobalCategory, id: category_id) do
      nil -> {:error, {:global_category, :not_found}}
      global_category -> {:ok, Brando.repo().preload(global_category, :globals)}
    end
  end

  @doc """
  Create new global category
  """
  @spec create_global_category(params) ::
          {:ok, global_category} | {:error, changeset}
  def create_global_category(global_category_params) do
    changeset = GlobalCategory.changeset(%GlobalCategory{}, global_category_params)

    changeset
    |> Brando.repo().insert()
    |> Cache.Globals.update()
    |> update_villains_referencing_global()
  end

  @doc """
  Update global category
  """
  @spec update_global_category(id :: any, params) ::
          {:ok, global_category} | {:error, changeset}
  def update_global_category(category_id, global_category_params) do
    {:ok, category} = get_global_category(category_id)
    changeset = GlobalCategory.changeset(category, global_category_params)

    changeset
    |> Brando.repo().update()
    |> Cache.Globals.update()
    |> update_villains_referencing_global()
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
