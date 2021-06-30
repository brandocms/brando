defmodule Brando.Sites.GlobalCategory do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Sites",
    schema: "GlobalCategory",
    singular: "global_category",
    plural: "global_categories",
    gettext_module: Brando.Gettext

  alias Brando.Sites.Global

  identifier "{{ entry.label }}"

  attributes do
    attribute :label, :string, required: true
    attribute :key, :string, required: true
  end

  relations do
    relation :globals, :has_many, module: Global, on_replace: :delete, cast: true
  end
end
