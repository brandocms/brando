# Compiled with the test support files, before protocol consolidation, for
# its traits; brando.gen_test generates public pages for it.
defmodule GeneratorStudio.Catalog.Article do
  use Brando.Blueprint,
    application: "GeneratorStudio",
    domain: "Catalog",
    schema: "Article",
    singular: "article",
    plural: "articles"

  trait Brando.Trait.Status
  trait Brando.Trait.Translatable
  trait Brando.Trait.Blocks
  trait Brando.Trait.Meta

  absolute_url ~H"/articles/{@entry.slug}"

  attributes do
    attribute :title, :string, required: true
    attribute :slug, :slug, required: true
  end

  relations do
    relation :blocks, :has_many, module: :blocks
    relation :bio_blocks, :has_many, module: :blocks
  end

  meta_schema do
    field ["title", "og:title"], & &1.title
    field "og:image", & &1.meta_image
  end
end
