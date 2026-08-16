defmodule Brando.Sites.DeployConfig do
  @moduledoc """
  Deployment settings for a site using static delivery.

  The embed lives with the public site registry. It is deliberately inert for
  dynamically delivered sites. Static builds snapshot this configuration so a
  later site edit cannot silently change how an already-built artifact deploys.

  `:rsync` targets are ordinary rsync destinations such as
  `deploy@example.com:/srv/www`; `:s3` targets use `s3://bucket/optional-prefix`.
  Florist application releases are configured separately.
  """

  use Ecto.Schema

  import Ecto.Changeset

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
    |> validate_http_url(:webhook_url)
  end

  defp require_target_for_strategy(changeset) do
    if get_field(changeset, :strategy), do: validate_required(changeset, [:target]), else: changeset
  end

  defp validate_strategy_target(changeset) do
    case {get_field(changeset, :strategy), get_field(changeset, :target)} do
      {:s3, target} when is_binary(target) ->
        case URI.parse(target) do
          %URI{scheme: "s3", host: host} when is_binary(host) and host != "" -> changeset
          _invalid -> add_error(changeset, :target, "must use s3://bucket/optional-prefix")
        end

      _other ->
        changeset
    end
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
