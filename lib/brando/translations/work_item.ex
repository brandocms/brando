defmodule Brando.Translations.WorkItem do
  @moduledoc """
  One field or item of a pending version that needs attention.

    * `:translate` — new content, seeded with the source text
    * `:review` — the source text changed; the translation was kept
    * `:shared_update` — a source-controlled value or media changed
    * `:awaiting_translation` — the source links to content that has no
      version in this language yet; the path ends in the source identifier id.
      It resolves itself when that version is created.

  `path` addresses the value, e.g. `"title"`,
  `"blocks/<sync_uid>/refs/lede/text"` or `"items/<uid>/label"`.
  `source_digest` is the source text the item was raised against.
  """
  use Ecto.Schema

  alias Brando.Translations.PendingVersion

  schema "translation_work_items" do
    belongs_to :pending_version, PendingVersion
    field :path, :string
    field :kind, Ecto.Enum, values: [:translate, :review, :shared_update, :awaiting_translation]
    field :source_digest, :string
    field :minor, :boolean, default: false
    field :resolved_at, :utc_datetime
    field :resolved_generation, :integer
    timestamps()
  end
end
