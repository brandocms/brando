defmodule Brando.MarkdownSources.Event do
  @moduledoc false
  use Ecto.Schema

  schema "content_markdown_events" do
    field :source_id, :integer
    field :version_id, :integer
    field :actor_id, :integer
    field :action, :string
    field :message, :string
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
