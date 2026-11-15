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

  `redirect_hosts` are hosts that redirect permanently to `domain`, such as
  `www.example.com` to `example.com`. Each follows the rules for `domain`,
  and an environment with any must have a domain. A host is bound once in the
  whole installation, as one environment's domain or one redirect host: the
  database refuses a second binding, also from concurrent writes (a trigger
  on `environments` under an advisory lock, besides the unique index on
  `domain`).
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
    field :redirect_hosts, {:array, :string}, default: []

    belongs_to :site, Site
    # Set only through `Brando.Assets.SiteAssets.activate_environment_set/2`
    # and `clear_environment_set/1`, never cast from a form
    belongs_to :asset_set, Brando.Assets.SiteAssetSet

    timestamps()
  end

  @required_fields [:site_id, :name, :key, :live]
  @optional_fields [:domain, :redirect_hosts]

  def changeset(environment \\ %__MODULE__{}, attrs) do
    environment
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> normalize_domain()
    |> validate_domain()
    |> normalize_redirect_hosts()
    |> validate_redirect_hosts()
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 1)
    |> validate_format(:key, @key_format)
    |> foreign_key_constraint(:site_id)
    |> unique_constraint([:site_id, :key])
    |> unique_constraint(:domain, message: gettext("Another environment already uses this host."))
    |> unique_constraint(:domain,
      name: :environments_domain_bound_once,
      message: gettext("Another environment already uses this host.")
    )
    |> unique_constraint(:redirect_hosts,
      name: :environments_redirect_hosts_bound_once,
      message: gettext("Another environment already uses one of these hosts, as its domain or a redirect host.")
    )
    |> check_constraint(:redirect_hosts,
      name: :environments_redirect_hosts_need_domain,
      message: gettext("An environment with redirect hosts needs a domain to redirect to.")
    )
    |> unique_constraint(:live, name: :environments_one_live_per_site_index)
  end

  @doc """
  The hosts in `text`, one per line or separated by commas or spaces, as the
  admin form takes them.
  """
  @spec parse_hosts(String.t() | nil) :: [String.t()]
  def parse_hosts(text) when is_binary(text), do: String.split(text, ~r/[\s,]+/, trim: true)
  def parse_hosts(_text), do: []

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

  defp normalize_redirect_hosts(changeset) do
    update_change(changeset, :redirect_hosts, fn
      hosts when is_list(hosts) ->
        hosts
        |> Enum.map(&(&1 |> String.trim() |> String.downcase()))
        |> Enum.reject(&(&1 == ""))
        |> Enum.uniq()

      hosts ->
        hosts
    end)
  end

  defp validate_redirect_hosts(changeset) do
    hosts = get_field(changeset, :redirect_hosts) || []
    domain = get_field(changeset, :domain)

    changeset =
      validate_change(changeset, :redirect_hosts, fn :redirect_hosts, hosts ->
        Enum.flat_map(hosts, &redirect_host_error(&1, domain))
      end)

    cond do
      hosts == [] or not is_nil(domain) ->
        changeset

      Map.has_key?(changeset.changes, :domain) ->
        add_error(
          changeset,
          :domain,
          gettext("Remove the redirect hosts first, or keep a domain: they redirect to it.")
        )

      true ->
        add_error(
          changeset,
          :redirect_hosts,
          gettext("An environment with redirect hosts needs a domain to redirect to.")
        )
    end
  end

  defp redirect_host_error(host, domain) do
    cond do
      not valid_host?(host) ->
        [
          redirect_hosts:
            gettext("%{host}: enter a host only, such as www.example.com, with no scheme, path, port or trailing dot.",
              host: host
            )
        ]

      InstallationHosts.member?(host) ->
        [
          redirect_hosts:
            gettext("%{host}: the installation itself uses this host, for its admin, media or CDN.", host: host)
        ]

      host == domain ->
        [redirect_hosts: gettext("%{host} is this environment's domain.", host: host)]

      true ->
        []
    end
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
