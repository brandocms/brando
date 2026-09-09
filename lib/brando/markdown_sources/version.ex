defmodule Brando.MarkdownSources.Version do
  @moduledoc "Immutable imported Markdown and safe rendered HTML, retained while sources exist."
  use Ecto.Schema

  schema "content_markdown_versions" do
    belongs_to :source, Brando.MarkdownSources.Source
    field :commit, :string
    field :content_hash, :string
    field :markdown, :string
    field :html, :string
    field :repository, :string
    field :path, :string
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
