defmodule Brando.Globals do
  @moduledoc """
  Globals
  """
  alias Brando.Cache
  alias Brando.Sites.GlobalCategory
  alias Brando.Villain

  import Ecto.Query

  @type changeset :: Ecto.Changeset.t()
  @type global_category :: Brando.Sites.GlobalCategory.t()
  @type params :: Map.t()

  @doc """
  Get global by key path
  """
  def get_global(key_path) do
    globals = Cache.Globals.get()

    case Map.fetch(globals, key_path) do
      {:ok, val} -> {:ok, val}
      :error -> {:error, {:global, :not_found}}
    end
  end

  @doc """
  Render global by key path
  """
  def render_global(key_path) do
    globals = Cache.Globals.get()

    case Map.fetch(globals, key_path) do
      {:ok, val} -> val
      :error -> ""
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
    search_terms = [
      "${GLOBAL:",
      "${global:"
    ]

    villains = Villain.list_villains()
    Villain.rerender_matching_villains(villains, search_terms)
    {:ok, global_category}
  end
end
