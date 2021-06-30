defmodule Brando.Navigation.Menu do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Navigation",
    schema: "Menu",
    singular: "menu",
    plural: "menus",
    gettext_module: Brando.Gettext

  trait Brando.Trait.Sequenced
  trait Brando.Trait.Timestamped
  trait Brando.Trait.Translatable

  identifier "{{ entry.title }} [{{ entry.language }}]"

  attributes do
    attribute :status, :status, required: true
    attribute :title, :string, required: true
    attribute :key, :string, required: true, unique: [prevent_collision: :language]
    attribute :template, :text
  end

  relations do
    relation :creator, :belongs_to, module: Brando.Users.User
    relation :items, :embeds_many, module: Brando.Navigation.Item, on_replace: :delete
  end
end
