defmodule Brando.Sites.Preview do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Sites",
    schema: "Preview",
    singular: "preview",
    plural: "previews"

  trait Brando.Trait.Creator
  trait Brando.Trait.Timestamped

  identifier "{{ entry.preview_key }}"
  absolute_url "{% route preview_url show { entry.preview_key } %}"

  attributes do
    attribute :preview_key, :text, required: true
    attribute :expires_at, :datetime, required: true
    attribute :html, :text, required: true
  end
end
