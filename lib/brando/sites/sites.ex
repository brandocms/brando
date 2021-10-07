defmodule Brando.Sites do
  @moduledoc """
  Context for Sites
  """
  use Brando.Query
  import Ecto.Query

  alias Brando.Cache
  alias Brando.Sites.GlobalSet
  alias Brando.Sites.Identity
  alias Brando.Sites.Preview
  alias Brando.Sites.SEO
  alias Brando.Villain

  @type id :: integer | binary
  @type params :: map
  @type changeset :: Ecto.Changeset.t()
  @type identity :: Brando.Sites.Identity.t()
  @type seo :: Brando.Sites.SEO.t()
  @type global_set :: Brando.Sites.GlobalSet.t()
  @type user :: Brando.Users.User.t()

  #
  # Identity

  query :list, Identity, do: fn query -> from(q in query) end

  filters Identity do
    fn
      {:language, language}, query ->
        from(q in query, where: q.language == ^language)
    end
  end

  query :single, Identity, do: fn q -> q end

  matches Identity do
    fn
      {:id, id}, query ->
        from t in query, where: t.id == ^id

      {:language, language}, query ->
        from t in query, where: t.language == ^language
    end
  end

  @doc """
  Create new identity
  """
  mutation :create, Identity

  @doc """
  Update existing identity
  """
  mutation :update, Identity do
    fn entry ->
      {:ok, entry}
      |> Cache.Identity.update()
      |> update_villains_referencing_identity()
    end
  end

  mutation :duplicate, {Identity, change_fields: [:name]}

  @doc """
  Create default identity
  """
  def create_default_identity do
    %Identity{
      name: "Organization name",
      alternate_name: "Short form",
      email: "mail@domain.tld",
      phone: "+47 00 00 00 00",
      address: "Testveien 1",
      zipcode: "0000",
      city: "Oslo",
      country: "NO",
      title_prefix: "CompanyName | ",
      title: "Welcome!",
      title_postfix: "",
      logo: nil,
      language: :en
    }
    |> Brando.repo().insert!
  end

  @doc """
  Try to get `name` from list of `links` in `identity`.
  """
  def get_link(name) do
    identity = Brando.Cache.get(:identity)
    Enum.find(identity.links, &(String.downcase(&1.name) == String.downcase(name))) || ""
  end

  def get_language(id) do
    identity = Brando.Cache.get(:identity)

    case Enum.find(identity.languages, &(&1.id == id)) do
      nil -> nil
      lang -> lang.name
    end
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
      identity: "{{ identity\.(.*?) }}",
      configs: "{{ configs\.(.*?) }}",
      links: "{{ links\.(.*?) }}",
      links_for: "{% for (.*?) in links\.(.*?) %}",
      configs_for: "{% for (.*?) in configs\.(.*?) %}",
      identity_for: "{% for (.*?) in identity\.(.*?) %}"
    ]

    villains = Villain.list_villains()

    # Check for instances in data fields
    Villain.rerender_matching_villains(villains, search_terms)

    # Check for instances in modules
    Villain.rerender_matching_modules(villains, search_terms)

    {:ok, identity}
  end

  #
  # SEO

  query :list, SEO, do: fn query -> from(q in query) end

  filters SEO do
    fn
      {:language, language}, query ->
        from(q in query, where: q.language == ^language)
    end
  end

  query :single, SEO, do: fn q -> q end

  matches SEO do
    fn
      {:id, id}, query ->
        from t in query, where: t.id == ^id

      {:language, language}, query ->
        from(q in query, where: q.language == ^language)
    end
  end

  @doc """
  Create new seo
  """
  mutation :create, SEO

  @doc """
  Update existing seo
  """
  mutation :update, SEO do
    fn entry ->
      {:ok, entry}
      |> Cache.SEO.update()

      #! TODO: |> update_villains_referencing_seo()
    end
  end

  mutation :duplicate, {SEO, change_fields: [:fallback_meta_title]}

  @doc """
  Create default seo
  """
  def create_default_seo, do: Brando.repo().insert!(%SEO{language: :en})

  #
  # Previews

  query :list, Preview, do: fn q -> q end
  query :single, Preview, do: fn q -> q end

  matches Preview do
    fn
      {:id, id}, query ->
        from t in query, where: t.id == ^id

      {:preview_key, preview_key}, query ->
        from t in query,
          where: t.preview_key == ^preview_key
    end
  end

  mutation :create, Preview
  mutation :update, Preview
  mutation :delete, Preview

  #
  # Global sets

  query :list, GlobalSet, do: fn query -> from(q in query) end

  filters GlobalSet do
    fn
      {:language, language}, query ->
        from(q in query, where: q.language == ^language)

      {:key, key}, query ->
        from(q in query, where: ilike(q.key, ^"%#{key}%"))

      {:label, label}, query ->
        from(q in query, where: ilike(q.label, ^"%#{label}%"))
    end
  end

  query :single, GlobalSet, do: fn query -> from(q in query) end

  matches GlobalSet do
    fn
      {:id, id}, query -> from(t in query, where: t.id == ^id)
      {:key, key}, query -> from(t in query, where: t.key == ^key)
    end
  end

  mutation :create, GlobalSet do
    fn entry ->
      {:ok, entry}
      |> Cache.Globals.update()
      |> update_villains_referencing_global()
    end
  end

  mutation :update, GlobalSet do
    fn entry ->
      {:ok, entry}
      |> Cache.Globals.update()
      |> update_villains_referencing_global()
    end
  end

  mutation :delete, GlobalSet

  @doc """
  Get global by category and key
  """
  def get_global(cat_key, key, globals) when is_map(globals) do
    case get_in(globals, [cat_key, key]) do
      nil -> {:error, {:global, :not_found}}
      val -> {:ok, val}
    end
  end

  def get_global(language, cat_key, key) do
    case get_in(Cache.Globals.get(language), [cat_key, key]) do
      nil -> {:error, {:global, :not_found}}
      val -> {:ok, val}
    end
  end

  @doc """
  Get global by key path
  """
  def get_global_path(key_path, globals) when is_map(globals) do
    case String.split(key_path, ".") do
      [cat_key, key] -> get_global(cat_key, key, globals)
      _ -> {:error, {:global, :not_found}}
    end
  end

  def get_global_path(language, key_path) do
    case String.split(key_path, ".") do
      [cat_key, key] -> get_global(cat_key, key, Cache.Globals.get(language))
      _ -> {:error, {:global, :not_found}}
    end
  end

  def get_global_path(key_path) do
    case String.split(key_path, ".") do
      [language, cat_key, key] -> get_global(cat_key, key, Cache.Globals.get(language))
      _ -> {:error, {:global, :not_found}}
    end
  end

  @doc """
  Get global, return global or empty string
  """
  def get_global_path!(key_path) do
    case get_global_path(key_path) do
      {:ok, global} -> global
      _ -> ""
    end
  end

  def get_global_path!(key_path, globals) do
    case get_global_path(key_path, globals) do
      {:ok, global} -> global
      _ -> ""
    end
  end

  @doc """
  Check all fields for references to GLOBAL
  Rerender if found.
  """
  @spec update_villains_referencing_global({:ok, global_set} | {:error, changeset}) ::
          {:ok, global_set} | {:error, changeset}
  def update_villains_referencing_global({:error, changeset}), do: {:error, changeset}

  def update_villains_referencing_global({:ok, global_set}) do
    search_terms = [globals: "{{ globals\.(.*?) }}"]

    villains = Villain.list_villains()
    Villain.rerender_matching_villains(villains, search_terms)
    Villain.rerender_matching_modules(villains, search_terms)

    {:ok, global_set}
  end
end
