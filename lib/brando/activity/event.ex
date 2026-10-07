defmodule Brando.Activity.Event do
  @moduledoc """
  One thing that happened to an entry: who did it (`user`), how (`source`),
  what (`action`), to which entry (`schema`, `entry_id`, with its `title` and
  `language` as they were), which fields changed, and the revision the change
  saved. Events that belong to one operation, such as a content import, share
  a `batch_id`. See `Brando.Activity`.
  """
  use Ecto.Schema

  @actions [
    :created,
    :updated,
    :published,
    :unpublished,
    :trashed,
    :restored,
    :deleted,
    :revision_restored,
    :duplicated,
    :imported,
    :reordered,
    :note_added,
    :note_resolved,
    :note_reopened
  ]

  @sources [:admin, :scheduler, :assistant, :mcp, :import, :system]

  @type t :: %__MODULE__{}

  schema "activity_events" do
    field :action, Ecto.Enum, values: @actions
    field :source, Ecto.Enum, values: @sources, default: :admin
    belongs_to :user, Brando.Users.User
    field :schema, :string
    field :entry_id, :integer
    field :title, :string
    field :language, :string
    field :fields, {:array, :string}, default: []
    field :revision, :integer
    field :details, :map, default: %{}
    field :batch_id, Ecto.UUID

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def actions, do: @actions
  def sources, do: @sources
end
