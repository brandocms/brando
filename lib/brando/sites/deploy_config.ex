defmodule Brando.Sites.DeployConfig do
  @moduledoc """
  Deployment settings for a site using static delivery.

  The embed lives with the public site registry. It is deliberately inert for
  dynamically delivered sites, but keeping one stable shape here lets the SSG
  and deploy phases build on the tenant foundation without another registry
  migration.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false

  @type t :: %__MODULE__{}

  embedded_schema do
    field :strategy, Ecto.Enum, values: [:s3, :rsync, :cloudflare_pages]
    field :target, :string
    field :cdn_url, :string
  end

  @fields [:strategy, :target, :cdn_url]

  def changeset(config, attrs) do
    cast(config, attrs, @fields)
  end
end
