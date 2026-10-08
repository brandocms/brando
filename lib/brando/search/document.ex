defmodule Brando.Search.Document do
  @moduledoc """
  One entry in one language in the admin search index (`Brando.Search`).

  The `document` column, a `tsvector`, is not a field here: it is written
  with the text by `Brando.Search.Indexer` and only read in queries.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "search_documents" do
    field :schema, Brando.Type.Module
    field :entry_id, :id
    field :language, :string
    field :config, :string
    field :title, :string
    field :slug, :string
    field :description, :string
    field :body, :string, load_in_query: false
    field :status, Brando.Type.Status
    field :cover, :string
    field :updated_at, :utc_datetime
    field :indexed_at, :utc_datetime_usec
  end
end
