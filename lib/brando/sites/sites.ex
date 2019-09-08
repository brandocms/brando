defmodule Brando.Sites do
  @moduledoc """
  Context for Sites
  """

  @type changeset :: Ecto.Changeset.t()
  @type id :: Integer.t() | String.t()
  @type organization :: Brando.Sites.Organization.t()
  @type params :: Map.t()
  @type user :: Brando.User.t()

  # ++header
  import Ecto.Query
  alias Brando.Sites.Organization
  alias Brando.Villain
  # __header

  # ++code
  @doc """
  Get organization
  """
  @spec get_organization() ::
          {:ok, organization} | {:error, {:organization, :not_found}}
  def get_organization do
    case Organization |> first() |> Brando.repo().one do
      nil -> {:error, {:organization, :not_found}}
      organization -> {:ok, organization}
    end
  end

  @doc """
  Create new organization
  """
  @spec create_organization(params, user | :system) ::
          {:ok, organization} | {:error, Ecto.Changeset.t()}
  def create_organization(organization_params, user \\ :system) do
    changeset = Organization.changeset(%Organization{}, organization_params, user)
    Brando.repo().insert(changeset)
  end

  @doc """
  Update existing organization
  """
  @spec update_organization(params, user | :system) ::
          {:ok, organization} | {:error, Ecto.Changeset.t()}
  def update_organization(organization_params, user \\ :system) do
    {:ok, organization} = get_organization()

    organization
    |> Organization.changeset(organization_params, user)
    |> Brando.repo().update()
    |> update_cache()
    |> update_villains_referencing_org()
  end

  @doc """
  Delete organization by id
  """
  @spec delete_organization :: {:ok, organization}
  def delete_organization() do
    {:ok, organization} = get_organization()
    Brando.repo().delete(organization)
    Brando.Images.Utils.delete_original_and_sized_images(organization, :image)
    Brando.Images.Utils.delete_original_and_sized_images(organization, :logo)
    {:ok, organization}
  end

  @doc """
  Create default organization
  """
  def create_default_organization do
    %Organization{
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

  @doc """
  Check all fields for references to `["${ORG:", "${CONFIG:", "${LINK:"]`.
  Rerender if found.
  """
  @spec update_villains_referencing_org(organization) :: [any]
  def update_villains_referencing_org(organization) do
    search_terms = ["${ORG:", "${CONFIG:", "${LINK:"]
    villains = Villain.list_villains()
    Villain.rerender_matching_villains(villains, search_terms)
    organization
  end

  @spec cache_organization :: {:error, boolean} | {:ok, boolean}
  def cache_organization do
    {:ok, organization} = get_organization()
    Cachex.put(:cache, :organization, organization)
  end

  @spec update_cache({:ok, organization} | {:error, changeset}) ::
          {:ok, organization} | {:error, changeset}
  def update_cache({:ok, updated_organization}) do
    Cachex.update(:cache, :organization, updated_organization)
    {:ok, updated_organization}
  end

  def update_cache({:error, changeset}), do: {:error, changeset}

  # __code
end
