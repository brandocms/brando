defmodule Brando.Sites.Preview do
  @moduledoc false
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
end
