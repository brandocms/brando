defmodule Brando.Sites do
  @moduledoc """
  Context for Sites
  """

  import Ecto.Query
  alias Brando.Images
  alias Brando.Sites.Identity
  alias Brando.Villain
  alias Brando.Sites.GlobalCategory

  @type changeset :: Ecto.Changeset.t()
  @type id :: Integer.t() | String.t()
  @type identity :: Brando.Sites.Identity.t()
  @type global_category :: Brando.Sites.GlobalCategory.t()
  @type params :: Map.t()
  @type user :: Brando.Users.User.t()

  @doc """
  Dataloader initializer
  """
  def data(_) do
    Dataloader.Ecto.new(
      Brando.repo(),
      query: &query/2
    )
  end

  @doc """
  Dataloader queries
  """
  def query(queryable, _), do: queryable

  @doc """
  Get identity
  """
  @spec get_identity() ::
          {:ok, identity} | {:error, {:identity, :not_found}}
  def get_identity do
    case Identity |> first() |> Brando.repo().one do
      nil -> {:error, {:identity, :not_found}}
      identity -> {:ok, identity}
    end
  end

  @doc """
  Create new identity
  """
  @spec create_identity(params, user | :system) ::
          {:ok, identity} | {:error, Ecto.Changeset.t()}
  def create_identity(identity_params, user \\ :system) do
    changeset = Identity.changeset(%Identity{}, identity_params, user)
    Brando.repo().insert(changeset)
  end

  @doc """
  Update existing identity
  """
  @spec update_identity(params, user | :system) :: {:ok, identity} | {:error, changeset}
  def update_identity(identity_params, user \\ :system) do
    {:ok, identity} = get_identity()

    identity
    |> Identity.changeset(identity_params, user)
    |> Brando.repo().update()
    |> update_cache()
    |> update_villains_referencing_identity()
  end

  @doc """
  Delete identity by id
  """
  @spec delete_identity :: {:ok, identity}
  def delete_identity() do
    {:ok, identity} = get_identity()
    Brando.repo().delete(identity)
    Images.Utils.delete_original_and_sized_images(identity, :image)
    Images.Utils.delete_original_and_sized_images(identity, :logo)

    {:ok, identity}
  end

  @doc """
  Create default identity
  """
  def create_default_identity do
    %Identity{
      name: "Organisasjonens navn",
      alternate_name: "Kortversjon av navnet",
      email: "mail@domain.tld",
      phone: "+47 00 00 00 00",
      address: "Testveien 1",
      zipcode: "0000",
      city: "Oslo",
      country: "NO",
      description: "Beskrivelse av organisasjonen/nettsiden",
      title_prefix: "Firma | ",
      title: "Velkommen!",
      title_postfix: "",
      image: nil,
      logo: nil,
      url: "https://www.domain.tld"
    }
    |> Brando.repo().insert!
  end

  def list_global_categories do
    {:ok, Brando.repo().all(GlobalCategory)}
  end

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
          {:ok, global_category} | {:error, Ecto.Changeset.t()}
  def create_global_category(global_category_params) do
    changeset = GlobalCategory.changeset(%GlobalCategory{}, global_category_params)
    Brando.repo().insert(changeset)
  end

  @doc """
  Update global category
  """
  @spec update_global_category(id :: any, params) ::
          {:ok, global_category} | {:error, Ecto.Changeset.t()}
  def update_global_category(category_id, global_category_params) do
    {:ok, category} = get_global_category(category_id)
    changeset = GlobalCategory.changeset(category, global_category_params)

    changeset
    |> Brando.repo().update()
    |> update_villains_referencing_global()
  end

  @doc """
  Try to get `name` from list of `links` in `identity`.
  """
  def get_link(name) do
    identity = Brando.Cache.get(:identity)
    Enum.find(identity.links, &(String.downcase(&1.name) == String.downcase(name)))
  end

  def get_global(key) do
    with {:ok, global_categories} <- get_global_categories(),
         {:ok, global} <- find_global(global_categories, key) do
      global
    else
      _ ->
        ""
    end
  end

  def find_global(globals, key) do
    with {:ok, category_key, key} <- split_globals_path(key),
         {:ok, category} <- find_global_category(globals, category_key),
         {:ok, global} <- find_global_key(category, key) do
      {:ok, global}
    else
      {:error, {:global_key, :not_found}} ->
        require Logger
        Logger.error("==> MISSING GLOBAL KEY: #{key} <==")
        {:error, {:global, :not_found}}

      {:error, {:global_category, :not_found}} ->
        require Logger
        Logger.error("==> MISSING GLOBAL CATEGORY: #{key} <==")
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

  @doc """
  Check all fields for references to IDENTITY, CONFIG and LINK
  Rerender if found.
  """
  @spec update_villains_referencing_identity({:ok, identity} | {:error, changeset}) ::
          {:ok, identity} | {:error, changeset}
  def update_villains_referencing_identity({:error, changeset}), do: {:error, changeset}

  def update_villains_referencing_identity({:ok, identity}) do
    search_terms = [
      "${IDENTITY:",
      "${CONFIG:",
      "${LINK:",
      "${identity:",
      "${config:",
      "${link:"
    ]

    villains = Villain.list_villains()
    Villain.rerender_matching_villains(villains, search_terms)
    {:ok, identity}
  end

  @spec cache_identity :: {:error, boolean} | {:ok, boolean}
  def cache_identity do
    {:ok, identity} = get_identity()
    Cachex.put(:cache, :identity, identity)
  end

  @spec update_cache({:ok, identity} | {:error, changeset}) ::
          {:ok, identity} | {:error, changeset}
  def update_cache({:ok, updated_identity}) do
    Cachex.update(:cache, :identity, updated_identity)
    {:ok, updated_identity}
  end

  def update_cache({:error, changeset}), do: {:error, changeset}
end
