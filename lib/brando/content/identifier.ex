defmodule Brando.Content.Identifier do
  @moduledoc """
  Schema for content identifiers

  Due to cyclic dependencies, this is a regular embedded ecto schema instead of a blueprint
  """
  use Ecto.Schema
  import Ecto.Changeset

  @fields ~w(
    entry_id
    title
    status
    language
    cover
    url
    schema
    updated_at
  )a

  @derive {Jason.Encoder, only: @fields}
  schema "content_identifiers" do
    field :entry_id, :id
    field :schema, Brando.Type.Module
    field :title, :string
    field :status, Brando.Type.Status
    field :language, Brando.Type.Atom
    field :cover, :string
    field :url, :string
    field :updated_at, :utc_datetime
  end

  def changeset(struct, params \\ %{}) do
    cast(struct, params, @fields)
  end

  def has_trait(Brando.Trait.SoftDelete), do: false

  def preloads_for(schema) do
    schema.__relations__()
    |> Enum.filter(&(&1.type == :entries))
    |> Enum.map(&{&1.name, [:identifier]})
  end
end
