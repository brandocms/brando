defmodule Brando.Sites do
  @moduledoc """
  Context for Sites
  """

  import Ecto.Query

  alias Brando.Cache
  alias Brando.Sites.Identity
  alias Brando.Sites.SEO
  alias Brando.Villain

  @type changeset :: Ecto.Changeset.t()
  @type id :: integer | binary
  @type identity :: Brando.Sites.Identity.t()
  @type seo :: Brando.Sites.SEO.t()
  @type params :: map
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
      nil ->
        {:error, {:identity, :not_found}}

      identity ->
        languages =
          Enum.map(Brando.config(:languages), fn [value: id, text: name] ->
            %{id: id, name: name}
          end)

        {:ok, Map.put(identity, :languages, languages)}
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
    |> Cache.Identity.update()
    |> update_villains_referencing_identity()
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
      title_prefix: "Firma | ",
      title: "Velkommen!",
      title_postfix: "",
      logo: nil
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

  @deprecated """
  Use Brando.Globals.render_global(key_path) instead
  """
  def get_global(key_path) do
    Brando.Globals.render_global(key_path)
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

    # Check for instances in templates
    Villain.rerender_matching_templates(villains, search_terms)

    {:ok, identity}
  end

  @doc """
  Get seo
  """
  @spec get_seo() ::
          {:ok, seo} | {:error, {:seo, :not_found}}
  def get_seo do
    case SEO |> first() |> Brando.repo().one do
      nil -> {:error, {:seo, :not_found}}
      seo -> {:ok, seo}
    end
  end

  @doc """
  Create new seo
  """
  @spec create_seo(params, user | :system) ::
          {:ok, seo} | {:error, Ecto.Changeset.t()}
  def create_seo(seo_params, user \\ :system) do
    changeset = Identity.changeset(%SEO{}, seo_params, user)
    Brando.repo().insert(changeset)
  end

  @doc """
  Update existing seo
  """
  @spec update_seo(params, user | :system) :: {:ok, seo} | {:error, changeset}
  def update_seo(seo_params, user \\ :system) do
    {:ok, seo} = get_seo()

    seo
    |> SEO.changeset(seo_params, user)
    |> Brando.repo().update()
    |> Cache.SEO.update()

    #! TODO: |> update_villains_referencing_seo()
  end

  @doc """
  Create default seo
  """
  def create_default_seo do
    %SEO{}
    |> Brando.repo().insert!
  end
end
