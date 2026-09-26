defmodule Brando.AI.Agent.Conversation do
  @moduledoc """
  One user's conversation with the content agent in a site/environment.

  `attachments` are `%{"alias" => "image1", "kind" => "image", "id" => 12,
  "label" => "lobby.jpg"}` maps; aliases are assigned when media is attached,
  never by upload completion order. `proposal_id` is the proposal version
  under review. `target` is the entry the conversation was opened for from
  the block editor, if any: `%{"content_type" => …, "id" => …, "field" => …,
  "title" => …, "language" => …}` (see `Brando.AI.Agent.target/2`).
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @schema_prefix "public"
  schema "ai_conversations" do
    field :scope, :string
    field :actor_id, :integer
    field :title, :string
    field :language, :string
    field :proposal_id, :binary_id
    field :attachments, {:array, :map}, default: []
    field :target, :map
    field :archived_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end
end
