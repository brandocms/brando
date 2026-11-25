defmodule Brando.SSG.PreviewHost do
  @moduledoc """
  A host of its own for each static site's build previews, from one pattern
  for the installation:

      config :brando, Brando.SSG, preview_host: "{site_key}.preview.example.com"

  A build's preview runs the build's scripts with the page's origin
  (`Brando.SSG.PreviewController`), so it opens only on a host of its own
  site. A site deployed elsewhere (`rsync`, `s3`) points its public domain at
  the static host, not at the installation, and without this it would need an
  environment with a domain routed to the installation just to see its
  builds. With the pattern, every active `:static` site has a preview host,
  `<site key>.<base>`, which one wildcard DNS record covers.

  The pattern names `{site_key}` once, as the whole first label, followed by
  a host name of at least two labels. It applies with `tenancy_mode: :multi`
  only, where `problems/0` lists what is wrong with it and boot refuses it
  (`validate_config!/0`): a pattern of another form, or one an installation
  host (`Brando.Tenant.InstallationHosts`) matches.

  A host an environment binds, as its domain or a redirect host, is never a
  preview host while it is bound, also when it matches the pattern: the site
  whose key it carries then has none. A site key longer than a DNS label (63
  bytes), or a host longer than 253 bytes, gives no preview host either.

  This module is the only one that reads the pattern.
  """

  alias Brando.Environments.Environment
  alias Brando.Exception.ConfigError
  alias Brando.Sites.Site
  alias Brando.Tenant
  alias Brando.Tenant.Cache

  @placeholder "{site_key}"
  @label_max_length 63
  @host_max_length 253

  @typedoc """
  What is wrong with the configured pattern: it does not name `{site_key}`
  once, as its whole first label (`:placeholder`), what follows is no host
  name of two labels or more (`:base`), or an installation host matches it
  (`{:installation_host, host}`).
  """
  @type problem :: :placeholder | :base | {:installation_host, String.t()}

  @doc "The configured pattern, as written, or nil."
  @spec pattern() :: String.t() | nil
  def pattern do
    case Application.get_env(:brando, Brando.SSG, [])[:preview_host] do
      pattern when is_binary(pattern) -> if String.trim(pattern) == "", do: nil, else: pattern
      _unset -> nil
    end
  end

  @doc """
  Whether sites get preview hosts: a pattern of the right form is set, and
  `tenancy_mode` is `:multi`.
  """
  @spec enabled?() :: boolean()
  def enabled?, do: match?({:ok, _base}, base())

  @doc """
  What is wrong with the configured pattern, with `tenancy_mode: :multi`:
  nothing (`[]`) when it is unset or right.
  """
  @spec problems() :: [problem()]
  def problems do
    case pattern() && Tenant.mode() == :multi && parse(pattern()) do
      {:ok, base} -> installation_hosts_under(base)
      {:error, problem} -> [problem]
      _off -> []
    end
  end

  @doc """
  Raises a `Brando.Exception.ConfigError` when the configured pattern has a
  problem (`problems/0`). Run at boot by `Brando.Tenant.validate_config!/0`.
  """
  @spec validate_config!() :: :ok
  def validate_config! do
    case problems() do
      [] -> :ok
      [problem | _] -> raise ConfigError, message: config_error(problem)
    end
  end

  @doc """
  The preview host of `site`, or nil: an active `:static` site whose key
  fits a DNS label and whose host fits a host name, unless an environment
  binds that host.
  """
  @spec host(Site.t()) :: String.t() | nil
  def host(%Site{status: :active, delivery_mode: :static, key: key}) do
    with {:ok, base} <- base(),
         true <- label?(key),
         host = key <> "." <> base,
         true <- byte_size(host) <= @host_max_length,
         false <- bound?(host) do
      host
    else
      _none -> nil
    end
  end

  def host(%Site{}), do: nil

  @doc """
  Whether `host` is a preview host: it matches the pattern and no environment
  binds it. Letter case and a trailing dot do not matter.
  """
  @spec preview_host?(String.t() | nil) :: boolean()
  def preview_host?(host), do: site_key(host) != nil and not bound?(normalize(host))

  @doc """
  The site a preview host is for: `{:ok, site}` for the active `:static` site
  with the key the host names, `:error` for a preview host with no such site,
  and nil for a host that is no preview host (`preview_host?/1`). Read from
  `Brando.Tenant.Cache`.
  """
  @spec site(String.t() | nil) :: {:ok, Site.t()} | :error | nil
  def site(host) do
    if preview_host?(host) do
      key = site_key(host)

      case Cache.get_site(key) do
        %Site{} = site -> if host(site) == normalize(host), do: {:ok, site}, else: :error
        nil -> :error
      end
    end
  end

  @doc """
  The preview hosts of every site in the registry that has one (`host/1`),
  sorted, for the served hosts file (`Brando.Tenant.ServedHosts`). Read from
  this node's cache.
  """
  @spec hosts() :: [String.t()]
  def hosts do
    if enabled?(),
      do: Cache.list_sites() |> Enum.map(&host/1) |> Enum.reject(&is_nil/1) |> Enum.sort(),
      else: []
  end

  @doc """
  The sites that have no preview host though the pattern is set, each with
  why: `{site, :key_too_long}` (a key longer than a DNS label),
  `{site, :host_too_long}` (a host longer than 253 bytes), or
  `{site, {:bound, other_site}}` (an environment of `other_site` binds the
  host). Only active `:static` sites count; empty when the pattern is off.
  """
  @spec unserved_sites() :: [{Site.t(), :key_too_long | :host_too_long | {:bound, Site.t()}}]
  def unserved_sites do
    case enabled?() && base() do
      {:ok, base} ->
        for %Site{status: :active, delivery_mode: :static} = site <- Cache.list_sites(),
            reason = unserved_reason(site, base),
            do: {site, reason}

      _off ->
        []
    end
  end

  defp unserved_reason(site, base) do
    host = site.key <> "." <> base

    cond do
      not label?(site.key) -> :key_too_long
      byte_size(host) > @host_max_length -> :host_too_long
      owner = binding_site(host) -> {:bound, owner}
      true -> nil
    end
  end

  @doc """
  The wildcard DNS record that covers every preview host (`*.<base>`), or
  nil when the pattern is off.
  """
  @spec wildcard() :: String.t() | nil
  def wildcard do
    case base() do
      {:ok, base} -> "*." <> base
      _off -> nil
    end
  end

  @doc """
  The host name every preview host ends in, after `{site_key}.`, or nil when
  the pattern is off.
  """
  @spec base_host() :: String.t() | nil
  def base_host do
    case base() do
      {:ok, base} -> base
      _off -> nil
    end
  end

  @doc """
  Whether `host` matches the pattern, bound or not: one label in the site
  key's format followed by the pattern's base. A new environment domain or
  redirect host must not (`Brando.Environments.Environment`).
  """
  @spec matches?(String.t() | nil) :: boolean()
  def matches?(host), do: site_key(host) != nil

  # The site key `host` names under the pattern, or nil
  defp site_key(host) when is_binary(host) do
    host = normalize(host)

    with {:ok, base} <- base(),
         true <- byte_size(host) <= @host_max_length,
         suffix = "." <> base,
         true <- String.ends_with?(host, suffix),
         key = binary_part(host, 0, byte_size(host) - byte_size(suffix)),
         true <- label?(key) do
      key
    else
      _no_match -> nil
    end
  end

  defp site_key(_host), do: nil

  defp label?(key), do: Tenant.valid_key?(key) and byte_size(key) <= @label_max_length

  # Read on every request a plug before the router sees, so the
  # installation's hosts are left to boot (`validate_config!/0`)
  defp base do
    with pattern when is_binary(pattern) <- pattern(),
         :multi <- Tenant.mode() do
      parse(pattern)
    end
  end

  defp parse(pattern) do
    case normalize(pattern) do
      @placeholder <> "." <> base ->
        cond do
          String.contains?(base, ["{", "}"]) -> {:error, :placeholder}
          String.contains?(base, ".") and Environment.valid_host?(base) -> {:ok, base}
          true -> {:error, :base}
        end

      _other ->
        {:error, :placeholder}
    end
  end

  defp installation_hosts_under(base) do
    suffix = "." <> base

    Brando.Tenant.InstallationHosts.list()
    |> Enum.filter(fn host ->
      String.ends_with?(host, suffix) and
        label?(binary_part(host, 0, byte_size(host) - byte_size(suffix)))
    end)
    |> Enum.uniq()
    |> Enum.map(&{:installation_host, &1})
  end

  # Bound as an environment's domain or redirect host, of an active site or
  # not, as `Brando.Plug.Tenant` resolves it before the pattern
  defp bound?(host), do: binding_site(host) != nil

  defp binding_site(host) do
    Enum.find(Cache.list_sites(), fn site ->
      Enum.any?(site.environments, fn environment ->
        normalize(environment.domain) == host or host in (environment.redirect_hosts || [])
      end)
    end)
  end

  defp normalize(host) when is_binary(host), do: host |> String.trim() |> String.downcase() |> String.trim_trailing(".")
  defp normalize(_host), do: nil

  defp config_error(:placeholder) do
    """
    Invalid `preview_host` in `config :brando, Brando.SSG`: #{inspect(pattern())}.

    The pattern names {site_key} once, as the whole first label, so that each
    static site's previews have an origin of their own:

        config :brando, Brando.SSG, preview_host: "{site_key}.preview.example.com"
    """
  end

  defp config_error(:base) do
    """
    Invalid `preview_host` in `config :brando, Brando.SSG`: #{inspect(pattern())}.

    After `{site_key}.` comes a host name of at least two labels, such as
    `preview.example.com`, with no scheme, port or path.
    """
  end

  defp config_error({:installation_host, host}) do
    """
    Invalid `preview_host` in `config :brando, Brando.SSG`: #{inspect(pattern())}.

    The installation's own host #{host} matches it, so a site's previews could
    open on the admin's origin. Choose a base no installation host is directly
    under, such as `{site_key}.preview.example.com`.
    """
  end
end
