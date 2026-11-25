defmodule Brando.Sites.DeployConfig do
  @moduledoc """
  Deployment settings for a site using static delivery.

  The embed lives with the public site registry. It is deliberately inert for
  dynamically delivered sites. Static builds snapshot this configuration so a
  later site edit cannot silently change how an already-built artifact deploys.

  `:local` is served by the installation itself (`Brando.SSG.LocalDelivery`)
  and has no target: a deploy records the build as the site's published
  build, and copies nothing. It writes nowhere outside the site's own
  directory, so it needs no list of destinations; an operator turns it off
  for every site with

      config :brando, Brando.Sites.DeployConfig, local_delivery: false

  `:rsync` targets are remote rsync destinations, `[user@]host:/absolute/path`
  such as `deploy@example.com:/srv/www`, reached over SSH on `:port` (22
  unless set) with the site's own key and accepted host keys
  (`Brando.SSG.SSH`); `:s3` targets use
  `s3://bucket/optional-prefix`. Florist application releases are configured
  separately.

  An rsync deploy mirrors the build with `--delete`, deleting only what
  Brando uploaded or an admin confirmed and never a path on `:keep_paths`
  (`Brando.SSG.TargetReview`): relative paths, a directory's ending in `/`,
  `.well-known/` and `cgi-bin/` unless changed, at most 100. With
  `:htaccess`, for an Apache or LiteSpeed host, a deploy writes the build's
  redirects, 404 page and caching into Brando's block in the target's
  `.htaccess` and leaves `_redirects.json` out (`Brando.SSG.TargetHtaccess`).
  Anyone who may
  deploy can set the target, so it is held
  to that remote form: no local paths, no loopback hosts, no `..` in the
  path, no rsync daemon or URL syntax, and no user or host that rsync or ssh
  could read as an option. An S3 deploy deletes every key under its target
  with the application's one set of credentials, so its prefix has no `.`,
  `..` or empty segment either.

  An operator lists the destinations each site may use, in config no admin
  can edit. `{site_key}` stands for the key of the site being saved or
  deployed, which binds an entry to that site. A target must be an entry, or
  lie under one ending in `/`; a bucket with no prefix passes only an entry
  naming it exactly:

      config :brando, Brando.Sites.DeployConfig,
        rsync_targets: ["deploy@static.example.com:/srv/sites/{site_key}"],
        s3_targets: ["s3://static-bucket/sites/{site_key}"]

  An entry without the placeholder grants every site: with
  `deploy@static.example.com:/srv/sites/`, one site can name another's
  directory. Destinations not named by the site key go in a map from each
  site's key to its own entries, and a site the map does not name gets none:

      config :brando, Brando.Sites.DeployConfig,
        s3_targets: %{"acme" => ["s3://acme-www"], "beta" => ["s3://beta-www"]}

  A site also has its own allowed targets, which an installation superuser
  sets under Sites (`Brando.Tenant.Registry.update_site_deploy_targets/4`)
  and no site administrator can change: `:allowed_rsync_targets` and
  `:allowed_s3_targets` on `Brando.Sites.Site`. Each entry is an exact
  destination or a parent ending in `/`, in the form a target takes, and
  names no `{site_key}`, as it already belongs to the site. A target passes
  when config allows it or the site's own entries do.

  A parent in one site's entries grants that site everything under it, other
  sites' directories included, so keep the sites' entries apart.

  An entry names a user, host and path, not a port: a target on any port
  passes, as the site's key opens only what its public key was installed on.

  With `tenancy_mode: :multi` no `:rsync` or `:s3` target passes unless
  config or the site's own entries allow it. With one site, an unset config
  list allows any target of the right form.

  An rsync target's host is looked up to refuse one that reaches this
  server, when a save sets the strategy or the target (`changeset/4` with
  `lookup_host: true`, as `Brando.Tenant.Registry` saves it), not while a
  form validates or when a save leaves both as they were. Each
  address family is looked up in the hosts file, and when it has no entry
  there, asked of the name servers through `:inet_res`. A name the name
  servers say does not exist, or that has no address records, passes: the
  system's resolver may still know it, and a deploy to a name nothing
  knows fails to connect. A name server that fails (SERVFAIL) or
  refuses, a query that times out, or no name server to ask, is a lookup
  that failed, and refuses the save, as the host could not be checked. Both
  families get one time limit together, `:lookup_timeout` (3 seconds), and a
  lookup it cuts short failed too. An answer is kept on the node for 60
  seconds, so saving again reuses it; a failed one is not kept. Each deploy
  looks the host up afresh (`valid_rsync_target?/2`).
  """

  use Ecto.Schema
  use Gettext, backend: Brando.Gettext

  import Ecto.Changeset

  alias Brando.Tenant.ServedHosts.DNS
  alias Brando.Webhooks.URLGuard
  alias Brando.Webhooks.Webhook

  @primary_key false

  @type t :: %__MODULE__{}

  @typedoc """
  The site a target is checked for: its key, which config's `{site_key}`
  stands for, or the site itself (`Brando.Sites.Site`), whose own allowed
  targets count too.
  """
  @type site :: String.t() | nil | %{required(:key) => String.t() | nil, optional(atom()) => term()}

  embedded_schema do
    field :strategy, Ecto.Enum, values: [:local, :s3, :rsync, :cloudflare_pages]
    field :target, :string
    field :port, :integer, default: 22
    field :cdn_url, :string
    field :webhook_url, :string
    field :auto_deploy, :boolean, default: false
    field :retention_count, :integer, default: 10
    field :keep_paths, {:array, :string}, default: [".well-known/", "cgi-bin/"]
    field :htaccess, :boolean, default: false
  end

  @fields [:strategy, :target, :port, :cdn_url, :webhook_url, :auto_deploy, :retention_count, :keep_paths, :htaccess]

  @keep_paths_limit 100

  @lookup_timeout :timer.seconds(3)
  @lookup_kept :timer.seconds(60)

  @doc """
  Changeset for the deployment settings of `site`: a site key, or the site
  with its own allowed targets (see `t:site/0`).
  With `lookup_host: true`, for a save that changes the strategy or the
  target, an rsync target's host is looked up too (see the moduledoc);
  without it, as while a form validates, it is not.
  """
  def changeset(config, attrs, site, opts \\ []) do
    changeset = cast(config, attrs, @fields)

    # A save that leaves the strategy and target as they were does not wait
    # on their host: each deploy looks it up anyway
    lookup =
      if Keyword.get(opts, :lookup_host, false) and
           (changed?(changeset, :strategy) or changed?(changeset, :target)),
         do: :kept,
         else: :none

    changeset
    |> require_target_for_strategy()
    |> validate_local_delivery()
    |> validate_strategy_target(site, lookup)
    |> validate_number(:port, greater_than_or_equal_to: 1, less_than_or_equal_to: 65_535)
    |> validate_number(:retention_count, greater_than_or_equal_to: 1, less_than_or_equal_to: 100)
    |> validate_keep_paths()
    |> validate_http_url(:cdn_url)
    |> validate_webhook_url()
  end

  # Paths an rsync deploy never deletes (`Brando.SSG.TargetReview`)
  defp validate_keep_paths(changeset) do
    changeset
    |> update_change(:keep_paths, &Enum.uniq/1)
    |> validate_length(:keep_paths, max: @keep_paths_limit)
    |> validate_change(:keep_paths, fn :keep_paths, paths ->
      case Enum.reject(paths, &Brando.SSG.TargetPaths.keep_entry?/1) do
        [] -> []
        [path | _rest] -> [keep_paths: gettext("has a path that is not plain: %{path}", path: inspect(path))]
      end
    end)
  end

  # Served from the site's own directory: there is nothing to name
  defp require_target_for_strategy(changeset) do
    case get_field(changeset, :strategy) do
      nil -> changeset
      :local -> put_change(changeset, :target, nil)
      _strategy -> validate_required(changeset, [:target])
    end
  end

  defp validate_local_delivery(changeset) do
    if get_field(changeset, :strategy) == :local and not local_delivery_allowed?(),
      do: add_error(changeset, :strategy, gettext("is turned off on this installation")),
      else: changeset
  end

  @doc """
  Whether this installation lets a site be served by the installation
  itself (`:local`): unless the operator's config sets `local_delivery:
  false`. Checked when the config is saved and again before each deploy.
  """
  @spec local_delivery_allowed?() :: boolean()
  def local_delivery_allowed?, do: Application.get_env(:brando, __MODULE__, [])[:local_delivery] != false

  defp validate_strategy_target(changeset, site, lookup) do
    case {get_field(changeset, :strategy), get_field(changeset, :target)} do
      {:s3, target} when is_binary(target) ->
        case s3_target_error(target, site) do
          nil -> changeset
          message -> add_error(changeset, :target, message)
        end

      {:rsync, target} when is_binary(target) ->
        case rsync_target_error(target, site, lookup) do
          nil -> changeset
          message -> add_error(changeset, :target, message)
        end

      _other ->
        changeset
    end
  end

  # A user and host that cannot start with `-`, and an absolute path of plain
  # characters: rsync hands the path to a remote shell, and the user and host
  # to ssh. A path may not start `//`, which makes `rsync://` a daemon URL.
  @rsync_target ~r/\A(?:(?<user>[A-Za-z0-9_][A-Za-z0-9._-]{0,63})@)?(?<host>[A-Za-z0-9](?:[A-Za-z0-9.-]{0,252})|\[[0-9A-Fa-f:.]+\]):(?<path>\/(?!\/)[A-Za-z0-9._~+@\/-]*)\z/

  @doc """
  Whether `target` is an rsync target `site` (see `t:site/0`) may deploy
  to: the remote `[user@]host:/absolute/path` form, on a host other than this
  one, and allowed by the operator's `rsync_targets` or the site's own
  `:allowed_rsync_targets`. Checked when the config
  is saved and again before each deploy, since builds snapshot the config:
  here with a fresh lookup of the host, which refuses a host that cannot be
  looked up.
  """
  @spec valid_rsync_target?(term(), site()) :: boolean()
  def valid_rsync_target?(target, site), do: check_rsync_target(target, site) == :ok

  @doc """
  As `valid_rsync_target?/2`, telling a target refused from one whose host
  could not be looked up, which may pass on another try.
  """
  @spec check_rsync_target(term(), site()) :: :ok | {:error, :invalid | :lookup_failed}
  def check_rsync_target(target, site) when is_binary(target) do
    with nil <- rsync_target_error(target, site, :none),
         %{"host" => host} <- Regex.named_captures(@rsync_target, target) do
      case local_host(host, :fresh) do
        :remote -> :ok
        :local -> {:error, :invalid}
        :lookup_failed -> {:error, :lookup_failed}
      end
    else
      _refused -> {:error, :invalid}
    end
  end

  def check_rsync_target(_target, _site), do: {:error, :invalid}

  @doc """
  The host of an rsync target in the remote form, as ssh is given it: an
  IPv6 literal without its brackets. Nil for any other target.
  """
  @spec rsync_host(term()) :: String.t() | nil
  def rsync_host(target) when is_binary(target) do
    case Regex.named_captures(@rsync_target, target) do
      %{"host" => host} -> host |> String.trim_leading("[") |> String.trim_trailing("]")
      nil -> nil
    end
  end

  def rsync_host(_target), do: nil

  # A bucket of plain characters, and a prefix that reaches S3 as written: no
  # query or fragment for a parser to drop, no escapes, no unexpanded `{...}`.
  @s3_target ~r/\As3:\/\/(?<bucket>[A-Za-z0-9][A-Za-z0-9._-]{0,254})(?<path>\/[^\x00-\x20\x7f?#%\\{}]*)?\z/

  @doc """
  The bucket and prefix of an S3 target `site` (see `t:site/0`) may deploy
  to, allowed by the operator's `s3_targets` or the site's own
  `:allowed_s3_targets`. Checked when the config is saved
  and again before each deploy, since builds snapshot the config.
  """
  @spec s3_destination(term(), site()) :: {:ok, String.t(), String.t()} | :error
  def s3_destination(target, site) when is_binary(target) do
    with nil <- s3_target_error(target, site), {:ok, bucket, prefix} <- parse_s3_target(target) do
      {:ok, bucket, prefix}
    else
      _refused -> :error
    end
  end

  def s3_destination(_target, _site), do: :error

  defp s3_target_error(target, site) do
    case parse_s3_target(target) do
      {:ok, bucket, prefix} -> destination_error(:s3_targets, site, &s3_within?(bucket, prefix, &1))
      :error -> gettext("must use s3://bucket/optional-prefix")
    end
  end

  defp parse_s3_target(target) do
    case Regex.named_captures(@s3_target, target) do
      %{"bucket" => bucket, "path" => path} when path in ["", "/"] ->
        {:ok, bucket, ""}

      %{"bucket" => bucket, "path" => path} ->
        prefix = path |> String.replace_prefix("/", "") |> String.replace_suffix("/", "")
        if prefix |> String.split("/") |> Enum.any?(&(&1 in ["", ".", ".."])), do: :error, else: {:ok, bucket, prefix}

      nil ->
        :error
    end
  end

  # The listed bucket and prefix itself, or for an entry ending in `/` a prefix
  # under it (not the one that holds the others): `s3://bucket` names the whole
  # bucket, and `s3://bucket/` every prefix in it, for one site or for all.
  defp s3_within?(bucket, prefix, listed) when is_binary(listed) do
    case parse_s3_target(listed) do
      {:ok, ^bucket, listed_prefix} ->
        cond do
          not String.ends_with?(listed, "/") -> prefix == listed_prefix
          listed_prefix == "" -> prefix != ""
          true -> String.starts_with?(prefix, listed_prefix <> "/")
        end

      _other ->
        false
    end
  end

  defp s3_within?(_bucket, _prefix, _listed), do: false

  defp rsync_target_error(target, site, lookup) do
    case Regex.named_captures(@rsync_target, target) do
      %{"host" => host} = parts ->
        cond do
          error = rsync_form_error(parts) -> error
          error = destination_error(:rsync_targets, site, &within?(parts, &1)) -> error
          lookup == :none -> nil
          true -> resolved_host_error(host, lookup)
        end

      nil ->
        gettext("must be a remote destination, user@host:/absolute/path")
    end
  end

  # What a target and an entry are both held to, before any list is read
  defp rsync_form_error(%{"host" => host, "path" => path}) do
    cond do
      not plain_path?(path) -> gettext("must be an absolute path without . or ..")
      local_host(host, :none) == :local -> gettext("must be on another server")
      true -> nil
    end
  end

  @doc """
  Why `entry` cannot be one of a site's own allowed targets for `setting`
  (`:rsync_targets` or `:s3_targets`), or nil: it is held to the form a
  target is, and may end in `/` to allow what lies under it. It names no
  `{site_key}`: the entry already belongs to its site.
  """
  @spec allowed_entry_error(:rsync_targets | :s3_targets, term()) :: String.t() | nil
  def allowed_entry_error(_setting, entry) when not is_binary(entry), do: gettext("must be text")

  def allowed_entry_error(setting, entry) do
    cond do
      String.contains?(entry, "{site_key}") ->
        gettext("needs no {site_key}: the entry already belongs to this site")

      setting == :rsync_targets ->
        case Regex.named_captures(@rsync_target, entry) do
          %{} = parts -> rsync_form_error(parts)
          nil -> gettext("must be a remote destination, user@host:/absolute/path")
        end

      setting == :s3_targets ->
        if parse_s3_target(entry) == :error, do: gettext("must use s3://bucket/optional-prefix")
    end
  end

  # `/srv/www` or `/srv/www/`: not the root, and no `.`, `..` or empty
  # segment, any of which could name a directory above the one it seems to
  defp plain_path?(path) do
    segments = path |> String.replace_suffix("/", "") |> String.split("/") |> tl()
    segments != [] and not Enum.any?(segments, &(&1 in ["", ".", ".."]))
  end

  # This server under another name. Names are only the start: the server's
  # own hostname or a wildcard DNS name reaches it too, so the host is also
  # resolved (with `lookup` other than `:none`) and refused if any address it
  # has is this server's. Only an operator's `rsync_targets` rules out every
  # such name.
  defp local_host(host, lookup) do
    host =
      host
      |> String.trim_leading("[")
      |> String.trim_trailing("]")
      |> String.trim_trailing(".")
      |> String.downcase()

    first_label = host |> String.split(".") |> hd()

    cond do
      host == "" -> :local
      first_label in ["localhost", "localhost4", "localhost6", "ip6-localhost", "ip6-loopback"] -> :local
      String.ends_with?(host, ".localhost") -> :local
      numeric_host?(host) -> local_or_remote(local_literal?(:inet.parse_strict_address(String.to_charlist(host))))
      lookup == :none -> :remote
      true -> resolved_host(host, lookup)
    end
  end

  defp local_or_remote(true), do: :local
  defp local_or_remote(false), do: :remote

  # An address however written (`127.1`, `0177.0.0.1`, `0x0`, an IPv6
  # literal): ssh's resolver reads all of them, so only the plain dotted or
  # IPv6 form, of another server, is a target
  defp numeric_host?(host) do
    String.contains?(host, ":") or
      host |> String.split(".") |> Enum.all?(&Regex.match?(~r/\A(0x[0-9a-f]*|[0-9]+)\z/, &1))
  end

  defp local_literal?({:ok, address}), do: local_addresses?([address])
  defp local_literal?({:error, _reason}), do: true

  defp resolved_host_error(host, lookup) do
    case local_host(host, lookup) do
      :remote -> nil
      :local -> gettext("must be on another server")
      :lookup_failed -> gettext("has a host that could not be looked up. Try again in a moment")
    end
  end

  defp resolved_host(host, lookup) do
    case lookup_addresses(host, lookup) do
      {:ok, addresses} -> local_or_remote(local_addresses?(addresses))
      :error -> :lookup_failed
    end
  end

  # A save reuses an answer for a minute; a deploy asks again
  defp lookup_addresses(host, :fresh), do: lookup_addresses(host)

  defp lookup_addresses(host, :kept) do
    key = {__MODULE__, :addresses, resolver(), host}

    case Cachex.get(:cache, key) do
      {:ok, addresses} when is_list(addresses) ->
        {:ok, addresses}

      _not_kept ->
        with {:ok, addresses} <- lookup_addresses(host) do
          Cachex.put(:cache, key, addresses, expire: @lookup_kept)
          {:ok, addresses}
        end
    end
  end

  # Both families at once, under one time limit. The resolver's own timeout
  # is not enough: the operating system's resolver does not heed it.
  defp lookup_addresses(host) do
    resolver = resolver()
    name = String.to_charlist(host)
    timeout = Application.get_env(:brando, __MODULE__, [])[:lookup_timeout] || @lookup_timeout
    tasks = for family <- [:inet, :inet6], do: Task.async(fn -> resolved(resolver, name, family) end)

    tasks
    |> Task.yield_many(timeout)
    |> Enum.map(fn {task, result} -> result || Task.shutdown(task, :brutal_kill) end)
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, {:ok, addresses}}, {:ok, found} -> {:cont, {:ok, found ++ addresses}}
      _failed_or_late, _found -> {:halt, :error}
    end)
  end

  defp resolver do
    Application.get_env(:brando, __MODULE__, [])[:resolver] || (&lookup_family/2)
  end

  @doc false
  # One family of `host`: its entries in the hosts file, or else its DNS
  # records, asked through `:inet_res` (`Brando.Tenant.ServedHosts.DNS`),
  # which tells a name with no records (`{:ok, []}`) from a lookup that
  # failed. The operating system's resolver reports both as `:nxdomain`.
  # Tests replace `:hosts` (as `:inet_hosts.gethostbyname/2`) and `:dns` (as
  # `:inet_res.resolve/5`).
  def lookup_family(host, family, opts \\ []) do
    hosts = Keyword.get(opts, :hosts, &:inet_hosts.gethostbyname/2)
    dns = Keyword.get(opts, :dns, &:inet_res.resolve/5)

    case hosts.(host, family) do
      {:ok, {:hostent, _name, _aliases, _type, _length, [_ | _] = addresses}} -> {:ok, addresses}
      _not_listed -> DNS.lookup_family(to_string(host), family, dns)
    end
  end

  # Loopback, unspecified, or one of this server's interfaces (an IPv4
  # address written as IPv6 too). A server behind NAT is not on its public
  # address: only `rsync_targets` rules that out.
  defp local_addresses?(addresses) do
    own = own_addresses()

    Enum.any?(addresses, fn address ->
      address = unmap(address)
      local_address?({:ok, address}) or address in own
    end)
  end

  defp unmap({0, 0, 0, 0, 0, 0xFFFF, high, low}), do: {div(high, 256), rem(high, 256), div(low, 256), rem(low, 256)}
  defp unmap(address), do: address

  # A name with no records here may still be one ssh knows (a `Host` alias in
  # its config): the operator's to answer for. Any other error is a lookup
  # that failed, as is one the time limit cuts short.
  defp resolved(resolver, host, family) do
    case resolver.(host, family) do
      {:ok, addresses} when is_list(addresses) -> {:ok, addresses}
      {:error, :nxdomain} -> {:ok, []}
      _failed -> :error
    end
  end

  defp own_addresses do
    case :inet.getifaddrs() do
      {:ok, interfaces} -> for {_name, opts} <- interfaces, {:addr, address} <- opts, do: unmap(address)
      {:error, _reason} -> []
    end
  end

  defp local_address?({:ok, {a, _, _, _}}), do: a in [0, 127]
  defp local_address?({:ok, {0, 0, 0, 0, 0, 0, 0, n}}), do: n in [0, 1]
  defp local_address?({:ok, _ipv6}), do: false

  # A target passes an entry of the site's own list, or config's. Config
  # unset: any target with one site, none with several, where a target could
  # be another site's. A map gives each site key its own list, and a site it
  # does not name gets none. Set to anything else: none, so a typo in the
  # config never opens it up. A site's own entries are matched as written:
  # none names `{site_key}`.
  defp destination_error(setting, site, within?) do
    {site_key, own} = grant(site)

    if Enum.any?(own_entries(own, setting), within?),
      do: nil,
      else: config_destination_error(setting, site_key, within?)
  end

  defp config_destination_error(setting, site_key, within?) do
    case setting_value(setting) do
      nil ->
        if Brando.Tenant.mode() == :multi, do: refused_message()

      targets when is_list(targets) or is_map(targets) ->
        if not Enum.any?(site_entries(targets, site_key), &within?.(for_site(&1, site_key))), do: refused_message()

      _misconfigured ->
        refused_message()
    end
  end

  # With several sites a superuser sets each one's under Sites
  defp refused_message do
    if Brando.Tenant.mode() == :multi,
      do:
        gettext(
          "is not a deploy target this site may use. A superuser sets the site's allowed deploy targets under Sites; the installation's config may list them too"
        ),
      else: gettext("must be a destination this installation deploys to")
  end

  # The site a target is checked for: its key alone, as config binds
  # `{site_key}` to it, or a site (`Brando.Sites.Site`, or a map with its
  # fields) whose own allowed targets count too
  defp grant(%{key: key} = site) do
    {key,
     %{
       rsync_targets: own_list(Map.get(site, :allowed_rsync_targets)),
       s3_targets: own_list(Map.get(site, :allowed_s3_targets))
     }}
  end

  defp grant(site_key), do: {site_key, %{}}

  defp own_list(entries) when is_list(entries), do: Enum.filter(entries, &is_binary/1)
  defp own_list(_entries), do: []

  defp own_entries(own, setting), do: Map.get(own, setting, [])

  defp site_entries(targets, _site_key) when is_list(targets), do: targets

  defp site_entries(targets, site_key) when is_binary(site_key) do
    case Map.get(targets, site_key) do
      entries when is_list(entries) -> entries
      _none -> []
    end
  end

  defp site_entries(_targets, _site_key), do: []

  @settings [:rsync_targets, :s3_targets]

  @doc """
  The entries of the operator's `setting` (`:rsync_targets` or
  `:s3_targets`) that apply to the site with key `site_key`, as they read for
  it: a list's entries with `{site_key}` filled in, those without it
  included, or the site's entries in a per-site map. A setting no target can
  pass gives none. For showing what config grants; a target is checked with
  `valid_rsync_target?/2` and `s3_destination/2`.
  """
  @spec configured_entries(:rsync_targets | :s3_targets, String.t()) :: [String.t()]
  def configured_entries(setting, site_key) when setting in @settings and is_binary(site_key) do
    case setting_value(setting) do
      targets when is_list(targets) or (is_map(targets) and not is_struct(targets)) ->
        for entry when is_binary(entry) <- site_entries(targets, site_key), do: for_site(entry, site_key)

      _unset_or_unreadable ->
        []
    end
  end

  @doc """
  Whether `target` passes for `site` as a save checks it, without looking
  its host up: for `:rsync` or `:s3`. A deploy also looks an rsync host up.
  """
  @spec allowed_target?(:rsync | :s3, term(), site()) :: boolean()
  def allowed_target?(:rsync, target, site) when is_binary(target), do: rsync_target_error(target, site, :none) == nil
  def allowed_target?(:s3, target, site) when is_binary(target), do: s3_target_error(target, site) == nil
  def allowed_target?(_strategy, _target, _site), do: false

  @doc """
  The entries of the operator's `rsync_targets` and `s3_targets` lists that
  grant every site, as `{setting, entry}`: those without `{site_key}`. Entries
  of a per-site map belong to their site, but see `overlapping_destinations/0`.
  """
  @spec shared_destinations() :: [{:rsync_targets | :s3_targets, String.t()}]
  def shared_destinations do
    for setting <- @settings,
        targets = setting_value(setting),
        is_list(targets),
        entry <- targets,
        is_binary(entry),
        not String.contains?(entry, "{site_key}"),
        do: {setting, entry}
  end

  @doc """
  Pairs of entries of two sites that reach the same destination, as
  `{setting, {site_key, entry, source}, {other_site_key, other_entry,
  other_source}}`: the same directory or prefix, or one inside the other,
  such as a parent of one site holding another site's directory. Either
  site's deploy replaces what the other's put there.

  An entry's `source` is `:config`, from a per-site map or from a list entry
  with `{site_key}`, which gives each of `sites` its own destination, or
  `:site`, from the site's own allowed targets. A list entry without the
  placeholder is every site's (`shared_destinations/0`), and is left out.

  Two sites' destinations from the same list entry that differ only in the
  rsync user, as `{site_key}@static.example.com:/www` gives them, are not
  reported as pairs: `account_bound_destinations/0` names such an entry once.
  The same place reached from two different entries is, whatever the users.
  """
  @spec overlapping_destinations([Brando.Sites.Site.t() | map()]) ::
          [{atom(), {String.t(), String.t(), :config | :site}, {String.t(), String.t(), :config | :site}}]
  def overlapping_destinations(sites \\ []) do
    Enum.flat_map(@settings, fn setting ->
      candidates =
        setting
        |> setting_entries(sites)
        |> Enum.with_index()
        |> Enum.flat_map(fn {entry, index} -> place(setting, entry, index) end)

      for {first, second} <- overlapping_pairs(setting, candidates), do: {setting, first.entry, second.entry}
    end)
  end

  # Where an entry deploys to, keyed by its host or bucket so only entries
  # in one are compared. A site's own entries are matched as written.
  defp place(setting, {key, entry, source, origin}, index) do
    destination = if source == :config, do: for_site(entry, key), else: entry

    case parse_place(setting, destination) do
      {:ok, group, user, path} ->
        [%{entry: {key, entry, source}, key: key, origin: origin, index: index, group: group, user: user, path: path}]

      :error ->
        []
    end
  end

  defp parse_place(:rsync_targets, destination) do
    case Regex.named_captures(@rsync_target, destination) do
      %{"user" => user, "host" => host, "path" => path} -> {:ok, host_key(host), user, String.trim_trailing(path, "/")}
      nil -> :error
    end
  end

  defp parse_place(:s3_targets, destination) do
    case parse_s3_target(destination) do
      {:ok, bucket, prefix} -> {:ok, bucket, nil, prefix}
      _error -> :error
    end
  end

  # Each candidate is looked for at its own path and at each that holds it,
  # so the work grows with the entries and their depth, not their pairs. In
  # the order entries are sorted (by site key), the first of each pair first.
  defp overlapping_pairs(setting, candidates) do
    candidates
    |> Enum.group_by(& &1.group)
    |> Enum.flat_map(fn {_group, members} ->
      by_path = Enum.group_by(members, & &1.path)

      for candidate <- members,
          path <- holding_paths(setting, candidate.path),
          other <- Map.get(by_path, path, []),
          other.key != candidate.key,
          {first, second} = Enum.min_max_by([candidate, other], & &1.index),
          same_account?(first, second),
          do: {first, second}
    end)
    |> Enum.uniq_by(fn {first, second} -> {first.index, second.index} end)
    |> Enum.sort_by(fn {first, second} -> {first.index, second.index} end)
  end

  # The path itself and each that holds it: `/srv/sites/acme` is held by
  # `/srv/sites`, `/srv` and `` (`/`). A whole bucket holds every prefix.
  defp holding_paths(:rsync_targets, path), do: path |> String.split("/") |> prefix_paths()
  defp holding_paths(:s3_targets, ""), do: [""]
  defp holding_paths(:s3_targets, prefix), do: ["" | prefix |> String.split("/") |> prefix_paths()]

  defp prefix_paths(parts), do: for(count <- 1..length(parts), do: parts |> Enum.take(count) |> Enum.join("/"))

  # From one list entry, two sites' destinations told apart by the user are
  # named once as the entry (`account_bound_destinations/0`)
  defp same_account?(%{origin: {:list, entry}, user: user}, %{origin: {:list, entry}, user: other}), do: user == other
  defp same_account?(_first, _second), do: true

  @doc """
  The entries of the operator's `rsync_targets` list that put `{site_key}` in
  the rsync user alone, as `{:rsync_targets, entry}`:
  `{site_key}@static.example.com:/www` gives every site the same host and
  path, each under its own account. Each site's deploy replaces the others'
  files there unless each account is confined to its own directory (chroot).
  """
  @spec account_bound_destinations() :: [{:rsync_targets, String.t()}]
  def account_bound_destinations do
    targets = setting_value(:rsync_targets)

    for entry when is_binary(entry) <- if(is_list(targets), do: targets, else: []),
        String.contains?(entry, "{site_key}"),
        {:ok, group, user, path} <- [parse_place(:rsync_targets, for_site(entry, "a"))],
        {:ok, ^group, other, ^path} <- [parse_place(:rsync_targets, for_site(entry, "b"))],
        user != other,
        do: {:rsync_targets, entry}
  end

  @doc """
  The settings with a part no target can pass: anything but a list of
  strings, or a map from string site keys to lists of strings. A value of
  another form refuses every target of its strategy; a map key that is not a
  string (`%{acme: [...]}`) or a value that is not a list refuses that site's.
  """
  @spec unreadable_settings() :: [atom()]
  def unreadable_settings do
    Enum.filter(@settings, fn setting ->
      case setting_value(setting) do
        nil -> false
        targets when is_list(targets) -> not Enum.all?(targets, &is_binary/1)
        targets when is_struct(targets) -> true
        targets when is_map(targets) -> not Enum.all?(targets, &readable_site_entries?/1)
        _other -> true
      end
    end)
  end

  defp setting_value(setting), do: Application.get_env(:brando, __MODULE__, [])[setting]

  defp readable_site_entries?({key, entries}),
    do: is_binary(key) and is_list(entries) and Enum.all?(entries, &is_binary/1)

  defp readable_site_entries?(_other), do: false

  # Each site's entries for `setting`, from the config map and its own list,
  # each with where it comes from
  defp setting_entries(setting, sites) do
    sites = for %{key: key} = site when is_binary(key) <- sites, do: site
    targets = setting_value(setting)

    configured =
      cond do
        is_list(targets) -> bound_entries(targets, sites)
        is_map(targets) and not is_struct(targets) -> map_entries(targets)
        true -> []
      end

    own =
      for site <- sites,
          {key, own} = grant(site),
          entry <- own_entries(own, setting),
          do: {key, entry, :site, :site}

    (configured ++ own) |> Enum.uniq() |> Enum.sort_by(&elem(&1, 0))
  end

  # A list entry with the placeholder, once for each site it names
  defp bound_entries(targets, sites) do
    for entry when is_binary(entry) <- targets,
        String.contains?(entry, "{site_key}"),
        %{key: key} <- sites,
        do: {key, entry, :config, {:list, entry}}
  end

  defp map_entries(targets) do
    for {key, entries} when is_binary(key) and is_list(entries) <- Enum.sort(targets),
        entry when is_binary(entry) <- entries,
        do: {key, entry, :config, :map}
  end

  # ssh reaches `example.com.` and `example.com`, or an IPv6 address however
  # written, as one host
  defp host_key(host) do
    host = host |> String.trim_leading("[") |> String.trim_trailing("]") |> String.trim_trailing(".") |> String.downcase()

    case :inet.parse_strict_address(String.to_charlist(host)) do
      {:ok, address} -> unmap(address)
      {:error, _reason} -> host
    end
  end

  # Without a key an entry keeps its placeholder, which no target can match
  defp for_site(listed, site_key) when is_binary(listed) and is_binary(site_key),
    do: String.replace(listed, "{site_key}", site_key)

  defp for_site(listed, _site_key), do: listed

  # The listed destination itself, or for an entry ending in `/` a directory
  # under it (not the directory itself, which holds the others). Hosts
  # compare without case.
  defp within?(%{"user" => user, "host" => host, "path" => path}, listed) when is_binary(listed) do
    case Regex.named_captures(@rsync_target, listed) do
      %{"user" => ^user, "host" => listed_host, "path" => listed_path} ->
        String.downcase(host) == String.downcase(listed_host) and
          if String.ends_with?(listed_path, "/"),
            do: String.starts_with?(path, listed_path) and String.trim(path, "/") != String.trim(listed_path, "/"),
            else: String.replace_suffix(path, "/", "") == listed_path

      _other ->
        false
    end
  end

  defp within?(_parts, _listed), do: false

  # Called after a deploy, so it may only reach a public address over https,
  # like a webhook (Brando.Webhooks.URLGuard). Checked when it changes, and
  # again before every delivery.
  defp validate_webhook_url(changeset) do
    validate_change(changeset, :webhook_url, fn
      :webhook_url, value when value in [nil, ""] ->
        []

      :webhook_url, value ->
        case URLGuard.resolve(value) do
          {:ok, _target} -> []
          {:error, reason} -> [webhook_url: {Webhook.url_error(reason), reason: reason}]
        end
    end)
  end

  defp validate_http_url(changeset, field) do
    validate_change(changeset, field, fn ^field, value -> http_url_errors(field, value) end)
  end

  defp http_url_errors(_field, value) when value in [nil, ""], do: []

  defp http_url_errors(field, value) do
    case URI.parse(value) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) -> []
      _invalid -> [{field, "must be an HTTP or HTTPS URL"}]
    end
  end
end
