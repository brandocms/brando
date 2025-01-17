defmodule Brando.Sites.Preview do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "Sites",
    schema: "Preview",
    singular: "preview",
    plural: "previews",
    gettext_module: Brando.Gettext

  trait Brando.Trait.Creator
  trait Brando.Trait.Timestamped

  identifier false
  persist_identifier false

  absolute_url "{% route preview_url show { entry.preview_key } %}"

  attributes do
    attribute :preview_key, :text, required: true
    attribute :expires_at, :datetime, required: true
    attribute :html, :text, required: true
  end
end
