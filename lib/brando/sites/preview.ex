defmodule Brando.Sites.Preview do
  @moduledoc """
  A shared preview: a snapshot of an entry's rendered page at a link for
  people without an admin account, until it expires. The link's key is kept
  only as its SHA-256 (`hash_key/1`): someone who reads the database cannot
  open the link.
  """
  use Brando.Blueprint,
    application: "Brando",
    domain: "Sites",
    schema: "Preview",
    singular: "preview",
    plural: "previews",
    gettext_module: Brando.Gettext

  trait :creator
  trait :timestamped

  identifier false
  persist_identifier false

  # Built from the key when the preview is shared; a stored preview has
  # only the key's hash
  absolute_url ~H|{route(:preview_url, :show, [@entry.preview_key])}|

  attributes do
    attribute :preview_key, :text, required: true
    attribute :expires_at, :datetime, required: true
    attribute :html, :text, required: true
  end

  relations do
    # The immutable frontend asset set the stored HTML was rendered against.
    # Legacy previews created before pinning keep a nil reference.
    relation :asset_set, :belongs_to, module: Brando.Assets.SiteAssetSet
  end

  @doc "What is stored of a preview's `key`, and looked up by: its SHA-256, in hex."
  @spec hash_key(String.t()) :: String.t()
  def hash_key(key) when is_binary(key), do: :sha256 |> :crypto.hash(key) |> Base.encode16(case: :lower)
end
