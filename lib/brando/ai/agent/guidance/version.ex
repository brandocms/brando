defmodule Brando.AI.Agent.Guidance.Version do
  @moduledoc """
  One saved version of a site/environment's assistant guidance, written in
  the admin. Versions are never changed; the latest of a scope is in use, and
  an empty `text` means the guidance was cleared.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @schema_prefix "public"
  schema "ai_guidance_versions" do
    field :scope, :string
    field :prefix, :string
    field :site_key, :string
    field :environment_key, :string
    field :text, :string, default: ""
    field :note, :string
    belongs_to :author, Brando.Users.User
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
