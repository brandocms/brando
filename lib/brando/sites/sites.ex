defmodule Brando.Sites do
  @moduledoc """
  Context for Sites
  """

  @type id :: Integer.t() | String.t()
  @type params :: Map.t()
  @type user :: Brando.User.t()

  # ++header
  import Ecto.Query
  alias Brando.Sites.Organization
  # __header

  # ++code
  @doc """
  Get organization
  """
  @spec get_organization() ::
          {:ok, Organization.t()} | {:error, {:organization, :not_found}}
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
          {:ok, Organization.t()} | {:error, Ecto.Changeset.t()}
  def create_organization(organization_params, user \\ :system) do
    changeset = Organization.changeset(%Organization{}, organization_params, user)
    Brando.repo().insert(changeset)
  end

  @doc """
  Update existing organization
  """
  @spec update_organization(params, user | :system) ::
          {:ok, Organization.t()} | {:error, Ecto.Changeset.t()}
  def update_organization(organization_params, user \\ :system) do
    {:ok, organization} = get_organization()

    organization
    |> Organization.changeset(organization_params, user)
    |> Brando.repo().update()
    |> update_cache()
  end

  @doc """
  Delete organization by id
  """
  @spec delete_organization :: {:ok, Organization.t()}
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

  @spec cache_organization :: {:error, boolean} | {:ok, boolean}
  def cache_organization do
    {:ok, organization} = get_organization()
    Cachex.put(:cache, :organization, organization)
  end

  @spec update_cache({:ok, Organization.t()}) :: {:ok, Organization.t()}
  def update_cache({:ok, updated_organization}) do
    Cachex.update(:cache, :organization, updated_organization)
    {:ok, updated_organization}
  end

  # __code
end
