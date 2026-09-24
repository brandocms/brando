defmodule Brando.Translations.PendingVersion do
  @moduledoc """
  A translation's next working version, computed from its source.

  `payload` is the target entry with the source's structure and shared values
  applied and its own translated text kept, encoded like a revision. The
  published entry is untouched until the translation is saved with it.

  A member has at most one `:pending` version. A newer one supersedes it and
  inherits its unresolved work items.
  """
  use Ecto.Schema

  alias Brando.Translations.Member
  alias Brando.Translations.WorkItem

  schema "translation_pending_versions" do
    belongs_to :member, Member
    field :source_generation, :integer
    field :source_fingerprint, :string
    field :base_fingerprint, :string
    field :schema_version, :integer, default: 0
    field :payload, :binary
    field :notes, {:array, :map}, default: []
    field :status, Ecto.Enum, values: [:pending, :applied, :superseded]
    field :applied_at, :utc_datetime
    has_many :work_items, WorkItem
    timestamps()
  end
end
