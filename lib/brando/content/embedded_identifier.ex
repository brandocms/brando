defmodule Brando.Content.EmbeddedIdentifier do
  @moduledoc """
  Schema for content identifiers

  Due to cyclic dependencies, this is a regular embedded ecto schema instead of a blueprint
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  @fields ~w(
    id
    title
    type
    absolute_url
    admin_url
    status
    language
    cover
    schema
    updated_at
  )a

  @derive {Jason.Encoder, only: @fields}
  embedded_schema do
    field :id, :id
    field :title, :string
    field :type, :string
    field :status, Brando.Type.Status
    field :language, :string
    field :absolute_url, :string
    field :admin_url, :string
    field :cover, :string
    field :schema, Brando.Type.Module
    field :updated_at, :utc_datetime
  end

  def changeset(struct, params \\ %{}) do
    cast(struct, params, @fields)
  end
end
