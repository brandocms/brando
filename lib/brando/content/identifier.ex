defmodule Brando.Content.Identifier do
  @moduledoc """
  Schema for content identifiers.

  This is a regular Ecto schema rather than a Blueprint so identifier generation does not
  introduce a compile-time dependency cycle back into the Blueprint system.
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

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: pos_integer() | nil,
          entry_id: pos_integer() | nil,
          schema: module() | nil,
          title: String.t() | nil,
          status: Brando.Type.Status.status() | nil,
          language: atom() | nil,
          cover: String.t() | nil,
          url: String.t() | nil,
          updated_at: DateTime.t() | nil
        }

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

  @doc """
  Builds a changeset for persisting an identifier snapshot.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(struct, params \\ %{}) do
    cast(struct, params, @fields)
  end

  @doc """
  Reports that identifiers do not implement the soft-delete trait.

  This compatibility callback lets query code treat identifiers like Blueprint-backed schemas.
  """
  @spec has_trait(Brando.Trait.SoftDelete) :: false
  def has_trait(Brando.Trait.SoftDelete), do: false

  @doc """
  Returns the identifier preloads required by entry relations on `schema`.
  """
  @spec preloads_for(module()) :: [{atom(), [:identifier]}]
  def preloads_for(schema) do
    schema
    |> Brando.Blueprint.Relations.__relations__()
    |> Enum.filter(&(&1.type == :entries))
    |> Enum.map(&{&1.name, [:identifier]})
  end

  @doc """
  Returns the module registry expected by shared schema and query helpers.
  """
  @spec __modules__() :: %{
          context: module(),
          application: module(),
          gettext: module(),
          schema: module(),
          admin_form_view: nil,
          admin_list_view: nil
        }
  def __modules__ do
    %{
      context: Brando.Content,
      application: Brando,
      gettext: Brando.Gettext,
      schema: Brando.Content.Identifier,
      admin_form_view: nil,
      admin_list_view: nil
    }
  end
end
