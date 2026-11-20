defmodule Brando.Translations.WorkItem do
  @moduledoc """
  One field or item of a pending version that needs attention.

    * `:translate` — new content, seeded with the source text, or text a new
      translation copied from the source (`Brando.Translations.create_target/5`).
      It stays `:translate` when the source changes the text before it is
      translated.
    * `:review` — the source text changed; the translation was kept
    * `:shared_update` — a source-controlled value or media changed
    * `:relinked` — the source is unchanged, but a link it holds now points
      at the version of the same content in this language
    * `:awaiting_translation` — the source links to content that has no
      version in this language yet; the path ends in the source identifier id.
      It resolves itself when that version is created.

  `path` addresses the value, e.g. `"title"`,
  `"blocks/<sync_uid>/refs/lede/text"` or `"items/<uid>/label"`.
  `source_digest` is the source text the item was raised against. A
  `:review` item's `source_previous` is the source's text before the change
  that raised it: the text the translation was last synced against, which it
  keeps when the source changes again before the review is done. It is nil
  for an item raised before brando_239, or by a member's first sync after it,
  and is cleared when the source moves to another translation, and when a
  save answers the review from a version the source has since changed: the
  text that version was computed against is not kept.
  """
  use Ecto.Schema

  alias Brando.Translations.PendingVersion

  schema "translation_work_items" do
    belongs_to :pending_version, PendingVersion
    field :path, :string
    field :kind, Ecto.Enum, values: [:translate, :review, :shared_update, :relinked, :awaiting_translation]
    field :source_digest, :string
    field :source_previous, :string
    field :minor, :boolean, default: false
    field :resolved_at, :utc_datetime
    field :resolved_generation, :integer
    timestamps()
  end
end
