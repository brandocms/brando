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
  could read as an option. An operator can further limit targets to the
  destinations they list, in config no admin can edit; a target must be one
  of them or lie under one ending in `/`:

      config :brando, Brando.Sites.DeployConfig,
        rsync_targets: ["deploy@static.example.com:/srv/sites/"]
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

  def changeset(config, attrs) do
    config
    |> cast(attrs, @fields)
    |> require_target_for_strategy()
    |> validate_strategy_target()
    |> validate_number(:retention_count, greater_than_or_equal_to: 1, less_than_or_equal_to: 100)
    |> validate_http_url(:cdn_url)
    |> validate_webhook_url()
  end

  defp require_target_for_strategy(changeset) do
    if get_field(changeset, :strategy), do: validate_required(changeset, [:target]), else: changeset
  end

  defp validate_strategy_target(changeset) do
    case {get_field(changeset, :strategy), get_field(changeset, :target)} do
      {:s3, target} when is_binary(target) ->
        case URI.parse(target) do
          %URI{scheme: "s3", host: host} when is_binary(host) and host != "" -> changeset
          _invalid -> add_error(changeset, :target, gettext("must use s3://bucket/optional-prefix"))
        end

      {:rsync, target} when is_binary(target) ->
        case rsync_target_error(target) do
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
  Whether `target` is an rsync target a deploy may use: the remote
  `[user@]host:/absolute/path` form, on a host other than this one, and
  among the operator's `rsync_targets` if they list them. Checked when the
  config is saved and again before each deploy, since builds snapshot the
  config.
  """
  @spec valid_rsync_target?(term()) :: boolean()
  def valid_rsync_target?(target), do: is_binary(target) and is_nil(rsync_target_error(target))

  defp rsync_target_error(target) do
    case Regex.named_captures(@rsync_target, target) do
      %{"host" => host, "path" => path} ->
        cond do
          ".." in String.split(path, "/") -> gettext("must be an absolute path without ..")
          local_host?(host) -> gettext("must be on another server")
          not listed_target?(target) -> gettext("must be a destination this installation deploys to")
          true -> nil
        end

      nil ->
        gettext("must be a remote destination, user@host:/absolute/path")
    end
  end

  # This server under another name. An address in a short or octal form
  # (`127.1`, `0177.0.0.1`), which ssh's resolver reads as loopback, is no
  # target either.
  defp local_host?(host) do
    host = host |> String.trim_leading("[") |> String.trim_trailing("]") |> String.downcase()
    address = String.to_charlist(host)

    cond do
      host == "localhost" or String.ends_with?(host, ".localhost") -> true
      match?({:ok, _}, :inet.parse_address(address)) -> local_address?(:inet.parse_strict_address(address))
      true -> false
    end
  end

  defp local_address?({:ok, {a, _, _, _}}), do: a in [0, 127]
  defp local_address?({:ok, {0, 0, 0, 0, 0, 0, 0, n}}), do: n in [0, 1]
  defp local_address?({:ok, {0, 0, 0, 0, 0, 0xFFFF, high, _}}), do: div(high, 256) in [0, 127]
  defp local_address?({:ok, _ipv6}), do: false
  defp local_address?({:error, _}), do: true

  defp listed_target?(target) do
    case Application.get_env(:brando, __MODULE__, [])[:rsync_targets] do
      targets when is_list(targets) ->
        Enum.any?(targets, fn
          listed when is_binary(listed) ->
            target == listed or (String.ends_with?(listed, "/") and String.starts_with?(target, listed))

          _listed ->
            false
        end)

      _unlimited ->
        true
    end
  end

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
