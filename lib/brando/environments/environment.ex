defmodule Brando.Environments.Environment do
  @moduledoc """
  A named content environment in Brando's public tenant registry.

  This record describes an environment; creation and migration of its
  PostgreSQL content schema belongs to the environment phase. Only one record
  per site may be marked live, enforced by a partial unique database index.

  `domain` decides which site answers on a host, and everything that resolves
  a host trusts it. A new value must be a bare host and not one the
  installation itself uses (`Brando.Tenant.InstallationHosts`); who may set it
  is `Brando.Tenant.Registry`'s check. A stored value is not checked again
  until it changes.
  """

  use Ecto.Schema
  use Gettext, backend: Brando.Gettext

  import Ecto.Changeset

  alias Brando.Sites.Site
  alias Brando.Tenant.InstallationHosts

  @schema_prefix "public"
  @timestamps_opts [type: :utc_datetime_usec]
  @key_format ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/
  @host_format ~r/\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*\z/
  @host_max_length 253

  @type t :: %__MODULE__{}

  schema "environments" do
    field :name, :string
    field :key, :string
    field :live, :boolean, default: false
    field :domain, :string

    belongs_to :site, Site

    timestamps()
  end

  @required_fields [:site_id, :name, :key, :live]
  @optional_fields [:domain]

  def changeset(environment \\ %__MODULE__{}, attrs) do
    environment
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> normalize_domain()
    |> validate_domain()
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 1)
    |> validate_format(:key, @key_format)
    |> foreign_key_constraint(:site_id)
    |> unique_constraint([:site_id, :key])
    |> unique_constraint(:domain, message: gettext("Another environment already uses this host."))
    |> unique_constraint(:live, name: :environments_one_live_per_site_index)
  end

  defp valid_host?(host), do: byte_size(host) <= @host_max_length and Regex.match?(@host_format, host)

  defp validate_domain(changeset) do
    validate_change(changeset, :domain, fn :domain, domain ->
      cond do
        not valid_host?(domain) ->
          [domain: gettext("Enter a host only, such as www.example.com, with no scheme, path, port or trailing dot.")]

        InstallationHosts.member?(domain) ->
          [domain: gettext("The installation itself uses this host, for its admin, media or CDN.")]

        true ->
          []
      end
    end)
  end

  defp normalize_domain(changeset) do
    update_change(changeset, :domain, fn
      domain when is_binary(domain) ->
        case domain |> String.trim() |> String.downcase() do
          "" -> nil
          normalized -> normalized
        end

      domain ->
        domain
    end)
  end
end
