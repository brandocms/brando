defmodule Brando.Translations.Member do
  @moduledoc """
  One entry's place in a translation group.

  `baseline` holds a digest per source text and shared-value path, taken from
  the source when this member was last synchronized. A source text whose digest
  has since moved is flagged for review.
  """
  use Ecto.Schema

  alias Brando.Translations.Group
  alias Brando.Translations.PendingVersion

  schema "translation_group_members" do
    belongs_to :group, Group
    field :entry_type, :string
    field :entry_id, :integer
    field :language, :string
    field :role, Ecto.Enum, values: [:source, :target]
    field :synchronized, :boolean, default: true
    field :detached_at, :utc_datetime
    field :last_synced_generation, :integer, default: 0
    field :baseline, :map, default: %{}
    has_many :pending_versions, PendingVersion
    timestamps()
  end
end
