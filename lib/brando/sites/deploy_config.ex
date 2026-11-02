defmodule Brando.Sites.DeployConfig do
  @moduledoc """
  Deployment settings for a site using static delivery.

  The embed lives with the public site registry. It is deliberately inert for
  dynamically delivered sites. Static builds snapshot this configuration so a
  later site edit cannot silently change how an already-built artifact deploys.

  `:rsync` targets are remote rsync destinations, `[user@]host:/absolute/path`
  such as `deploy@example.com:/srv/www`; `:s3` targets use
  `s3://bucket/optional-prefix`. Florist application releases are configured
  separately.

  An rsync deploy mirrors the build with `--delete` as the server's user and
  SSH identity, and anyone who may deploy can set the target, so it is held
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

  A parent in one site's entries grants that site everything under it, other
  sites' directories included, so keep the sites' entries apart.

  With `tenancy_mode: :multi` a strategy's list or map is required, and no
  target passes without it. With one site, an unset list allows any target of
  the right form.
  """

  use Ecto.Schema
  use Gettext, backend: Brando.Gettext

  import Ecto.Changeset

  alias Brando.Webhooks.URLGuard
  alias Brando.Webhooks.Webhook

  @primary_key false

  @type t :: %__MODULE__{}

  embedded_schema do
    field :strategy, Ecto.Enum, values: [:s3, :rsync, :cloudflare_pages]
    field :target, :string
    field :cdn_url, :string
    field :webhook_url, :string
    field :auto_deploy, :boolean, default: false
    field :retention_count, :integer, default: 10
  end

  @fields [:strategy, :target, :cdn_url, :webhook_url, :auto_deploy, :retention_count]

  @doc "Changeset for the deployment settings of the site with key `site_key`."
  def changeset(config, attrs, site_key) do
    config
    |> cast(attrs, @fields)
    |> require_target_for_strategy()
    |> validate_strategy_target(site_key)
    |> validate_number(:retention_count, greater_than_or_equal_to: 1, less_than_or_equal_to: 100)
    |> validate_http_url(:cdn_url)
    |> validate_webhook_url()
  end

  defp require_target_for_strategy(changeset) do
    if get_field(changeset, :strategy), do: validate_required(changeset, [:target]), else: changeset
  end

  defp validate_strategy_target(changeset, site_key) do
    case {get_field(changeset, :strategy), get_field(changeset, :target)} do
      {:s3, target} when is_binary(target) ->
        case s3_target_error(target, site_key) do
          nil -> changeset
          message -> add_error(changeset, :target, message)
        end

      {:rsync, target} when is_binary(target) ->
        case rsync_target_error(target, site_key) do
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
  Whether `target` is an rsync target the site with key `site_key` may deploy
  to: the remote `[user@]host:/absolute/path` form, on a host other than this
  one, and allowed by the operator's `rsync_targets`. Checked when the config
  is saved and again before each deploy, since builds snapshot the config.
  """
  @spec valid_rsync_target?(term(), String.t()) :: boolean()
  def valid_rsync_target?(target, site_key), do: is_binary(target) and is_nil(rsync_target_error(target, site_key))

  # A bucket of plain characters, and a prefix that reaches S3 as written: no
  # query or fragment for a parser to drop, no escapes, no unexpanded `{...}`.
  @s3_target ~r/\As3:\/\/(?<bucket>[A-Za-z0-9][A-Za-z0-9._-]{0,254})(?<path>\/[^\x00-\x20\x7f?#%\\{}]*)?\z/

  @doc """
  The bucket and prefix of an S3 target the site with key `site_key` may deploy
  to, allowed by the operator's `s3_targets`. Checked when the config is saved
  and again before each deploy, since builds snapshot the config.
  """
  @spec s3_destination(term(), String.t()) :: {:ok, String.t(), String.t()} | :error
  def s3_destination(target, site_key) when is_binary(target) do
    with nil <- s3_target_error(target, site_key), {:ok, bucket, prefix} <- parse_s3_target(target) do
      {:ok, bucket, prefix}
    else
      _refused -> :error
    end
  end

  def s3_destination(_target, _site_key), do: :error

  defp s3_target_error(target, site_key) do
    case parse_s3_target(target) do
      {:ok, bucket, prefix} -> destination_error(:s3_targets, site_key, &s3_within?(bucket, prefix, &1))
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

  defp rsync_target_error(target, site_key) do
    case Regex.named_captures(@rsync_target, target) do
      %{"host" => host, "path" => path} = parts ->
        cond do
          not plain_path?(path) -> gettext("must be an absolute path without . or ..")
          local_host?(host) -> gettext("must be on another server")
          true -> destination_error(:rsync_targets, site_key, &within?(parts, &1))
        end

      nil ->
        gettext("must be a remote destination, user@host:/absolute/path")
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
  # resolved and refused if any address it has is this server's. Only an
  # operator's `rsync_targets` rules out every such name.
  defp local_host?(host) do
    host =
      host
      |> String.trim_leading("[")
      |> String.trim_trailing("]")
      |> String.trim_trailing(".")
      |> String.downcase()

    first_label = host |> String.split(".") |> hd()

    cond do
      host == "" -> true
      first_label in ["localhost", "localhost4", "localhost6", "ip6-localhost", "ip6-loopback"] -> true
      String.ends_with?(host, ".localhost") -> true
      numeric_host?(host) -> local_literal?(:inet.parse_strict_address(String.to_charlist(host)))
      true -> resolves_locally?(host)
    end
  end

  # An address however written (`127.1`, `0177.0.0.1`, `0x0`, an IPv6
  # literal): ssh's resolver reads all of them, so only the plain dotted or
  # IPv6 form, of another server, is a target
  defp numeric_host?(host) do
    String.contains?(host, ":") or
      host |> String.split(".") |> Enum.all?(&Regex.match?(~r/\A(0x[0-9a-f]*|[0-9]+)\z/, &1))
  end

  defp local_literal?({:ok, address}), do: local_addresses?([address])
  defp local_literal?({:error, _reason}), do: true

  defp resolves_locally?(host) do
    resolver = Application.get_env(:brando, __MODULE__, [])[:resolver] || (&:inet.getaddrs(&1, &2, :timer.seconds(3)))
    [:inet, :inet6] |> Enum.flat_map(&resolved(resolver, host, &1)) |> local_addresses?()
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

  # A name that does not resolve here may still be one ssh knows (a `Host`
  # alias in its config): the operator's to answer for
  defp resolved(resolver, host, family) do
    case resolver.(String.to_charlist(host), family) do
      {:ok, addresses} -> addresses
      {:error, _reason} -> []
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

  # Unset: any target with one site, none with several, where a target could be
  # another site's. A map gives each site key its own list, and a site it does
  # not name gets none. Set to anything else: none, so a typo in the config
  # never opens it up.
  defp destination_error(setting, site_key, within?) do
    refused = gettext("must be a destination this installation deploys to")

    case Application.get_env(:brando, __MODULE__, [])[setting] do
      nil ->
        if Brando.Tenant.mode() == :multi, do: gettext("needs this installation's config to list its deploy destinations")

      targets when is_list(targets) or is_map(targets) ->
        if not Enum.any?(site_entries(targets, site_key), &within?.(for_site(&1, site_key))), do: refused

      _misconfigured ->
        refused
    end
  end

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
  Pairs of entries in a per-site map that reach the same destination for two
  sites, as `{setting, {site_key, entry}, {other_site_key, other_entry}}`: the
  same directory or prefix, or one inside the other, such as a parent under
  one key holding another key's directory. Either site's deploy replaces what
  the other's put there.
  """
  @spec overlapping_destinations() :: [{atom(), {String.t(), String.t()}, {String.t(), String.t()}}]
  def overlapping_destinations do
    for setting <- @settings,
        targets = setting_value(setting),
        is_map(targets),
        entries = map_entries(targets),
        {key, entry} <- entries,
        {other_key, other_entry} <- entries,
        key < other_key,
        same_place?(setting, for_site(entry, key), for_site(other_entry, other_key)),
        do: {setting, {key, entry}, {other_key, other_entry}}
  end

  @doc """
  The settings no target can pass, so every save and deploy of that strategy
  is refused: anything but a list of strings, or a map from string site keys
  to lists of strings (`%{acme: [...]}` with an atom key, for one).
  """
  @spec unreadable_settings() :: [atom()]
  def unreadable_settings do
    Enum.filter(@settings, fn setting ->
      case setting_value(setting) do
        nil -> false
        targets when is_list(targets) -> not Enum.all?(targets, &is_binary/1)
        targets when is_map(targets) -> not Enum.all?(targets, &readable_site_entries?/1)
        _other -> true
      end
    end)
  end

  defp setting_value(setting), do: Application.get_env(:brando, __MODULE__, [])[setting]

  defp readable_site_entries?({key, entries}),
    do: is_binary(key) and is_list(entries) and Enum.all?(entries, &is_binary/1)

  defp map_entries(targets) do
    for {key, entries} when is_binary(key) and is_list(entries) <- Enum.sort(targets),
        entry when is_binary(entry) <- entries,
        do: {key, entry}
  end

  # One host's or bucket's paths where either holds the other. A whole bucket,
  # or `s3://bucket/`, holds every prefix in it.
  defp same_place?(:rsync_targets, entry, other) do
    with %{"host" => host, "path" => path} <- Regex.named_captures(@rsync_target, entry),
         %{"host" => other_host, "path" => other_path} <- Regex.named_captures(@rsync_target, other) do
      String.downcase(host) == String.downcase(other_host) and
        nested?(String.trim_trailing(path, "/"), String.trim_trailing(other_path, "/"))
    else
      _unparsed -> false
    end
  end

  defp same_place?(:s3_targets, entry, other) do
    case {parse_s3_target(entry), parse_s3_target(other)} do
      {{:ok, bucket, prefix}, {:ok, bucket, other_prefix}} ->
        prefix == "" or other_prefix == "" or nested?(prefix, other_prefix)

      _other ->
        false
    end
  end

  defp nested?(path, other),
    do: path == other or String.starts_with?(path, other <> "/") or String.starts_with?(other, path <> "/")

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
