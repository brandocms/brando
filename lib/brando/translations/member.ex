defmodule Brando.Translations.Member do
  @moduledoc """
  One entry's place in a translation group.

  `baseline` holds a digest per source text and shared-value path, taken from
  the source when this member was last synchronized. A source text whose digest
  has since moved is flagged for review. `baseline_texts` holds the source's
  texts of that sync by path (text paths only), so a review item can carry the
  text the translation was written from (`WorkItem`'s `source_previous`). A
  member last synchronized before brando_239 has none until its next sync.
  The texts are not loaded with the member (`load_in_query: false`): only a
  sync reads them, and selects them itself.
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
    field :baseline_texts, :map, default: %{}, load_in_query: false
    has_many :pending_versions, PendingVersion
    timestamps()
  end
end
