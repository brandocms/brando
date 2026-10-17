# brando.gen_test and resource_render_test generate public pages for it. Not
# in test/support's compiled files: those are in every Blueprint list, and
# app-wide scans (SEO audit, alt text) would query its missing table. Defined
# after protocol consolidation, its traits' protocol implementations have no
# effect, which keeps it out of trait listings too.
ignore_consolidated = Code.get_compiler_option(:ignore_already_consolidated)
Code.put_compiler_option(:ignore_already_consolidated, true)

defmodule GeneratorStudio.Catalog.Article do
  use Brando.Blueprint,
    application: "GeneratorStudio",
    domain: "Catalog",
    schema: "Article",
    singular: "article",
    plural: "articles",
    gettext_module: Brando.Gettext

  trait Brando.Trait.Status
  trait Brando.Trait.Translatable
  trait Brando.Trait.Blocks
  trait Brando.Trait.Meta

  absolute_url ~H"/articles/{@entry.slug}"

  attributes do
    attribute :title, :string, required: true
    attribute :slug, :slug, required: true
  end

  assets do
    asset :cover, :image, cfg: %{}
  end

  relations do
    relation :blocks, :has_many, module: :blocks
    relation :bio_blocks, :has_many, module: :blocks
  end

  meta_schema do
    field ["title", "og:title"], & &1.title
    field "og:image", &fallback([&1.meta_image, &1.cover])
    # Raises on the generator's probe, whose entry has no title.
    field "description", &String.slice(&1.meta_description || &1.title, 0, 155)
  end
end

Code.put_compiler_option(:ignore_already_consolidated, ignore_consolidated)
