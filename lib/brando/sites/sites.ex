defmodule Brando.Sites do
  @moduledoc """
  Context for Sites
  """

  @type id :: Integer.t() | String.t()
  @type params :: Map.t()
  @type user :: Brando.User.t()

  # ++header
  import Ecto.Query
  alias Brando.Sites.Link
  alias Brando.Sites.Organization
  # __header

  # ++code
  @doc """
  List all links
  """
  @spec list_links() :: {:ok, [Link.t()]}
  def list_links do
    {:ok, Brando.repo().all(Link)}
  end

  @doc """
  Get single link
  """
  @spec get_link(id) ::
          {:ok, Link.t()} | {:error, {:link, :not_found}}
  def get_link(id) do
    case Brando.repo().get(Link, id) do
      nil -> {:error, {:link, :not_found}}
      link -> {:ok, link}
    end
  end

  @doc """
  Create new link
  """
  @spec create_link(params, user | :system) ::
          {:ok, Link.t()} | {:error, Ecto.Changeset.t()}
  def create_link(link_params, _user \\ :system) do
    changeset = Link.changeset(%Link{}, link_params)
    Brando.repo().insert(changeset)
  end

  @doc """
  Update existing link
  """
  @spec update_link(id, params, user | :system) ::
          {:ok, Link.t()} | {:error, Ecto.Changeset.t()}
  def update_link(link_id, link_params, _user \\ :system) do
    {:ok, link} = get_link(link_id)

    link
    |> Link.changeset(link_params)
    |> Brando.repo().update()
  end

  @doc """
  Delete link by id
  """
  @spec delete_link(id) ::
          {:ok, Link.t()}
  def delete_link(id) do
    {:ok, link} = get_link(id)
    Brando.repo().delete(link)

    {:ok, link}
  end

  @doc """
  Get organization
  """
  @spec get_organization() ::
          {:ok, Organization.t()} | {:error, {:organization, :not_found}}
  def get_organization do
    case Organization |> first() |> preload(:links) |> Brando.repo().one do
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
    require Logger
    Logger.error(inspect(organization_params, pretty: true))
    {:ok, organization} = get_organization()

    organization
    |> Organization.changeset(organization_params, user)
    |> Brando.repo().update()
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

  # __code
end
