# Brando CMS Usage Rules and Conventions (WIP - this is mostly AI slop...)

This document summarizes the key usage rules and conventions for using **Brando CMS** as a dependency in your Elixir/Phoenix project. It covers how to define content models (Blueprints), internationalization, query helpers, static site generation, CDN setup, live preview, and frontend utilities for images and videos. Follow these guidelines and best practices to integrate Brando’s public API effectively, and avoid common pitfalls.


#### CLAUDE START

## Blueprints

Blueprints are Brando's core abstraction for defining content schemas with auto-generated admin interfaces, APIs, and database migrations. They provide a declarative DSL for building complete content management systems.

### Blueprint Structure
A blueprint should be organized in this order:
1. **Attributes** - Schema fields and data types
2. **Assets** - File and image upload configurations  
3. **Relations** - Associations between schemas
4. **Listings** - Admin list view definitions
5. **Forms** - Admin form interface definitions
6. **Meta/JSON-LD** - SEO and structured data schemas
7. **Translations** - Internationalization setup
8. **Datasources** - Dynamic content queries (optional)

### Core Components

#### Attributes
Define schema fields with types and constraints:
```elixir
attributes do
  attribute :title, :string, required: true
  attribute :slug, :slug, required: true, unique: [prevent_collision: true]
  attribute :status, :enum, options: [draft: 0, published: 1, disabled: 2], default: :draft
  attribute :publish_at, :utc_datetime
  attribute :body, :text
  attribute :meta_data, :map
end
```

#### Assets  
Configure file and image uploads with module attributes:
```elixir
@image_cfg [
  allowed_mimetypes: ["image/jpeg", "image/png"],
  default_size: "medium",
  upload_path: Path.join(["images", "covers"]),
  random_filename: true,
  size_limit: 10_240_000,
  sizes: %{
    "thumb" => %{"size" => "150x150", "quality" => 65, "crop" => true},
    "medium" => %{"size" => "500x500", "quality" => 65, "crop" => true},
    "large" => %{"size" => "700x700", "quality" => 65, "crop" => true}
  },
  srcset: %{
    default: [
      {"medium", "500w"},
      {"large", "700w"}
    ]
  }
]

@file_cfg %{
  allowed_mimetypes: ["application/pdf"],
  upload_path: Path.join("files", "documents"),
  random_filename: false,
  size_limit: 10_240_000
}

assets do
  asset :cover, :image, cfg: @image_cfg
  asset :pdf_file, :file, cfg: @file_cfg
end
```

#### Relations
Define associations between schemas:
```elixir
relations do
  relation :category, :belongs_to, module: Category
  relation :tags, :many_to_many, module: Tag, join_through: "articles_tags"
  relation :comments, :has_many, module: Comment, preload_order: [desc: :inserted_at]
  relation :author, :belongs_to, module: User, cast: true
  relation :blocks, :has_many, module: :blocks
end
```

#### Listings
Configure admin list views:
```elixir
listings do
  listing do
    query %{
      order: [{:desc, :inserted_at}], 
      preload: [:category, :author]
    }
    
    sort :default, label: t("Default"), order: [{:desc, :inserted_at}]
    sort :title_asc, label: t("Title ↓"), order: "asc title"
    sort :title_desc, label: t("Title ↑"), order: "desc title"
    
    filter label: t("Title"), filter: "title"
    filter label: t("Status"), filter: "status"
    
    action label: t("Create entry"), event: "create_entry"
    action label: t("Duplicate"), event: "duplicate_entry"
    
    component &__MODULE__.listing_row/1
  end
end
```

#### Forms
Define admin form interfaces with blocks support:
```elixir
forms do
  form do
    default_params %{status: :draft}
    blocks :blocks, label: t("Content blocks")
    
    tab t("Content") do
      fieldset do
        input :status, :status, label: t("Status")
      end
      
      fieldset do
        size :half
        input :title, :text, label: t("Title")
        input :slug, :slug, label: t("Slug")
      end
      
      fieldset do
        input :cover, :image, label: t("Cover image")
        input :body, :textarea, label: t("Description")
      end
    end
    
    tab t("Meta") do
      fieldset do
        input :meta_title, :text, label: t("Meta title")
        input :meta_description, :textarea, label: t("Meta description")
      end
    end
  end
end
```

#### Meta Schema
SEO and social media metadata:
```elixir
meta_schema do
  field ["title", "og:title"], &fallback([Map.get(&1, :meta_title), Map.get(&1, :title)])
  field ["description", "og:description"], & &1.meta_description
  field "og:image", &Map.get(&1, :meta_image)
  field "og:locale", &encode_locale(try_path(&1, [:__meta__, :language]))
end
```

#### JSON-LD Schema  
Structured data for search engines:
```elixir
json_ld_schema JSONLD.Schema.Article do
  field :author, :identity
  field :copyrightHolder, :identity
  field :dateModified, :datetime, & &1.updated_at
  field :datePublished, :datetime, & &1.inserted_at
  field :description, :string, & &1.meta_description
  field :headline, :string, & &1.title
  field :inLanguage, :language
  field :name, :string, & &1.title
  field :url, :current_url
end
```

#### Translations
Internationalization configuration:
```elixir
translations do
  context :naming do
    translate :singular, t("article")
    translate :plural, t("articles")
  end
end
```

### Common Traits
Blueprints can include reusable traits:
- `Brando.Trait.Creator` - Adds creator tracking
- `Brando.Trait.Timestamped` - Adds inserted_at/updated_at
- `Brando.Trait.Status` - Adds status field with published/draft/disabled
- `Brando.Trait.Blocks` - Adds Villain block editor support
- `Brando.Trait.Meta` - Adds meta fields for SEO
- `Brando.Trait.SoftDelete` - Enables soft deletion
- `Brando.Trait.Sequenced` - Adds sequence/ordering
- `Brando.Trait.Translatable` - Adds multi-language support

### Blueprint Declaration
```elixir
defmodule MyApp.Projects.Project do
  use Brando.Blueprint,
    application: "MyApp",
    domain: "Projects", 
    schema: "Project",
    singular: "project",
    plural: "projects",
    gettext_module: MyAppWeb.Gettext

  trait Brando.Trait.Creator
  trait Brando.Trait.Timestamped
  trait Brando.Trait.Status
  trait Brando.Trait.Blocks
  
  # ... attributes, assets, relations, etc.
end
```

## Blocks/Villain Content Editor System

The **Brando Villain** system is a sophisticated block-based content management system that enables visual content editing with powerful templating capabilities. It combines a LiveView-based admin interface with a Liquid templating engine for flexible content rendering.

### System Overview

The Villain system consists of several interconnected components:
- **Blocks** - Individual content units (text, images, galleries, etc.)
- **Modules** - Reusable content components with module templates and configuration
- **Module Templates** - Liquid-based rendering code that transforms module data into HTML
- **Content Templates** - Pre-built collections of blocks used as starting points
- **Vars** - Dynamic typed inputs for module configuration
- **Refs** - Embedded block instances within modules
- **Module Sets** - Organizational collections of related modules

### Core Architecture

#### Blocks Foundation
Every content piece is a **Block** with these core properties:
```elixir
# Base block structure
%Block{
  uid: "unique-identifier",          # Unique block ID
  type: :module,                     # [:module, :container, :module_entry, :fragment]
  active: true,                      # Visibility toggle
  collapsed: false,                  # UI state in editor
  refs: [],                          # An embedded array of polymorphic embeds
}
```

**Built-in Ref Types:**
- `TextBlock` - Rich text content with markdown support
- `HeaderBlock` - Headings with levels, links, CSS classes
- `PictureBlock` - Images with captions, credits, and links
- `GalleryBlock` - Galleries with multiple configurations
- `VideoBlock` - Video embeds and file uploads
- `MediaBlock` - Image, gallery OR video

#### Content Modules
**Modules** are reusable content components that combine module templates with configurable elements:

```elixir
%Module{
  name: "Hero Section",
  namespace: "marketing", 
  help_text: "Main page hero with heading and call-to-action",
  code: """
  <section class="hero" style="background-color: {{ bg_color }}">
    <div class="container">
      {% ref refs.heading %}
      {% ref refs.description %}
      <a href="{{ cta_link }}" class="btn btn-primary">
        {{ cta_text }}
      </a>
    </div>
  </section>
  """,
  refs: [
    %{name: "heading", data: %HeaderBlock{level: 1}},
    %{name: "description", data: %TextBlock{}}
  ],
  vars: [
    %{key: "bg_color", type: :color, label: "Background Color"},
    %{key: "cta_text", type: :string, label: "Button Text"},
    %{key: "cta_link", type: :link, label: "Button Link"}
  ]
}
```

The `code` field contains the **module template** - Liquid code that renders the module's HTML output using variables and references.

### Variables (Vars) System

**Vars** provide typed inputs for dynamic module configuration:

#### Variable Types
```elixir
# String input
%{key: "title", type: :string, label: "Section Title"}

# Rich text editor  
%{key: "description", type: :text, label: "Description"}

# HTML editor
%{key: "content", type: :html, label: "Rich Content"}

# Image upload
%{key: "background", type: :image, label: "Background Image"}

# File upload
%{key: "brochure", type: :file, label: "PDF Brochure"}

# Color picker
%{key: "accent_color", type: :color, label: "Accent Color"}

# Select dropdown
%{
  key: "layout", 
  type: :select, 
  label: "Layout Style",
  options: [
    %{label: "Standard", value: "standard"},
    %{label: "Compact", value: "compact"}
  ]
}

# Boolean toggle
%{key: "show_border", type: :boolean, label: "Show Border"}

# Link with URL or internal reference
%{key: "more_info", type: :link, label: "More Info Link"}

# Layout sizing
%{key: "width", type: :select, options: [:full, :half, :third]}
```

#### Variable Access in Module Templates
Variables are accessible via `{{ variable_key }}` syntax:
```liquid
<h2 style="color: {{ title_color }}">{{ title }}</h2>
<div class="layout-{{ width }}">
  {{ content }}
</div>
```

### References (Refs) System

**Refs** embed actual block instances within modules, providing structured content areas:

```elixir
# Module with refs
refs: [
  %{name: "main_heading", data: %HeaderBlock{level: 1, text: "Default Title"}},
  %{name: "intro_text", data: %TextBlock{text: "Default description"}},
  %{name: "feature_image", data: %PictureBlock{}}
]
```

#### Ref Rendering in Module Templates
```liquid
<header>
  {% ref refs.main_heading %}
  {% ref refs.intro_text %}
</header>
<aside>
  {% ref refs.feature_image %}
</aside>
```

### Content Templates

**Content templates** (`Brando.Content.Template`) are pre-built collections of blocks that serve as starting points for content creation:

```elixir
%Template{
  name: "Landing Page Starter",
  namespace: "pages",
  blocks: [
    %Block{type: "module", data: %ModuleBlock{module_id: hero_module_id}},
    %Block{type: "module", data: %ModuleBlock{module_id: features_module_id}},
    %Block{type: "text", data: %TextBlock{text: "Add your content here..."}}
  ]
}
```

Content templates provide ready-made page layouts that editors can customize rather than building from scratch.

### LiveView Block Editor Architecture

The block editor uses a sophisticated LiveView component hierarchy with `send_update/2` for coordination:

#### Component Structure
```elixir
# Main form container
BlockField (id: "block-field-#{field_name}")
  └── Block (id: "block-#{uid}") 
      ├── ModulePicker (for adding new modules)
      ├── BlockSelector (for changing block types)  
      └── Child Blocks (recursive structure)
```

#### Communication Patterns
The system uses extensive `send_update/2` messaging for coordination:

```elixir
# Collect all changesets for form submission
send_update(BlockField, 
  id: "block-field-#{field_name}", 
  event: "fetch_root_blocks"
)

# Update block sequence/ordering
send_update(Block, 
  id: "block-#{uid}", 
  event: "update_sequence", 
  sequence: new_index
)

# Duplicate block with complex changeset gathering
send_update(Block, 
  id: source_id, 
  event: "fetch_changeset_for_duplication", 
  target_id: target_id
)

# Provide collected changesets back to parent
send_update(BlockField, 
  id: field_id, 
  event: "provide_root_blocks", 
  changesets: collected_changesets
)
```

#### Key Events Flow
1. **User adds block** → `ModulePicker` sends update to parent `Block`
2. **Block created** → Parent updates sequence of all siblings  
3. **Form submission** → `BlockField` collects all changesets via `fetch_root_blocks`
4. **Blocks respond** → Each block provides its changeset data
5. **Data persisted** → Complete block tree saved to database

### Liquid Templating Engine

Brando uses a custom Liquid parser (`Brando.Villain.LiquexParser`) with specialized tags for module templates.

#### Context Variables
Module templates have access to global context:
```liquid
{{ globals.site_name }}             . <!-- Global site variables -->
{{ identity.name }}                   <!-- Site identity info -->
{{ navigation.main_menu }}            <!-- Navigation menus -->
{{ entry.title }}                     <!-- Current entry data -->
{{ custom_variable }}            <!-- Module variables -->
```

### Rendering Pipeline

The complete flow from editor to HTML output:

#### 1. Content Creation
```elixir
# User creates/edits content in LiveView interface
BlockField → Block components → Form submission
```

#### 2. Data Persistence  
```elixir
# Changesets collected and saved
%Entry{
  blocks: [
    %Block{type: "module", data: %ModuleBlock{module_id: 123}},
    %Block{type: "text", data: %TextBlock{text: "Content"}}
  ]
}
```

#### 3. Render Trigger
```elixir
# Content change triggers rendering
Brando.Villain.render_entry(entry, opts)
```

#### 4. Block Processing
```elixir
# Each block type has dedicated parser
Brando.Villain.Parser.text(block_data, opts)
Brando.Villain.Parser.module(block_data, opts)  
Brando.Villain.Parser.picture(block_data, opts)
```

#### 5. Context Assembly
```elixir
# Build complete template context for module templates
%{
  "vars" => module_variables,
  "refs" => embedded_blocks,
  "globals" => site_globals,
  "identity" => site_identity,
  "navigation" => menu_data,
  "entry" => current_entry
}
```

#### 6. Module Template Execution
```elixir
# Process Liquid module templates
Liquex.parse_and_render(module.code, context)
```

#### 7. HTML Output
```elixir
# Final rendered HTML cached in database
%Entry{rendered_blocks: "<section><h1>Title</h1>...</section>"}
```

### Advanced Features

#### Datasources
External data integration for dynamic content in module templates. We configure 
the wanted datasource in the source module, which then becomes available as `entries`
in the template:
```liquid
{% datasource %}
  {% for post in entries %}
    <article>
      <h3>{{ post.title }}</h3>
      <p>{{ post.excerpt }}</p>
    </article>
  {% endfor %}
{% enddatasource %}
```

#### Containers & Palettes
- **Containers** - Wrapper blocks with custom CSS classes and styling
- **Palettes** - CSS variable-based color schemes for consistent theming

#### Content Fragments
Reusable block collections that can be embedded across multiple pages:
```liquid
{% fragment "global/footer" %}
{% fragment "shared/newsletter-signup" %}
```

#### Live Preview
Real-time rendering for admin interface with WebSocket updates showing changes immediately in preview panel.

### Summary

The Villain system provides powerful, flexible content management while maintaining clean separation between content structure (blocks), presentation (module templates), and configuration (vars/refs).


######## CLAUDE END

######## OPENAI START

## Blueprints: Defining Content Models

**Blueprints** in Brando serve as the definition of your content data models, combining an Ecto schema with additional metadata for forms, relations, and more. They are the core building blocks for content in Brando and provide a structured way to declare fields, relationships, and how content should behave in the admin UI.

### Defining a Blueprint Module

Start by creating an Elixir module for each content type (e.g., Article, Project, Page) and use `Brando.Blueprint`. A blueprint typically looks like:

```elixir
defmodule MyApp.Content.Article do
  use Brando.Blueprint,
    application: "MyApp",
    domain:      "Content",
    schema:      "Article",
    singular:    "article",
    plural:      "articles"

  # ... define attributes, relations, identifiers, forms, listings, meta etc. ...
end
```

`application`, `domain` and `schema help Brando categorize and reference your content, and `singular`/`plural` are used for route helpers and labels in the admin UI.

**Best practices**

* One blueprint per logical content entity.  
* Use meaningful `domain`/`schema` names so editors can find things easily.  
* Scaffold with `mix brando.gen.blueprint` and tweak.


### Attributes and Fields

Declare fields with `attribute/3` inside the blueprint:

```elixir
attribute :title, :string, required: true
attribute :slug, :slug, unique: [prevent_collision: true], required: true
attribute :type, :enum, values: [:full_case, :external_link], required: true
attribute :featured, :boolean
attribute :published_at, :datetime
```

Key conventions:

| Option          | Purpose                                                                    |
|-----------------|----------------------------------------------------------------------------|
| `required: true`| Enforced in the generated changeset and admin UI.                          |


### Relations

```elixir
relation :client, :belongs_to, module: MyApp.Clients.Client, required: true
relation :case_categories, :has_many,
  module: MyApp.Cases.CaseCategory,
  preload_order: [{:asc, :sequence}],
  drop_param: :drop_category_ids,
  sort_param: :sort_category_ids,
  on_replace: :delete_if_exists,
  cast: true

relation :blocks, :has_many, module: :blocks
relation :related_cases, :entries
```


### Forms (Admin UI)

```elixir
form do
  default_params %{status: :draft, type: :full_case}
  blocks :blocks, module_set: "Case", label: t("Blocks")

  tab "Content" do
    fieldset do
      size :full
      input :status, :status
    end

    fieldset do
      size :half

      input :type, :radios,
        options: [
          %{value: :full_case, label: t("Full Case")},
          %{value: :external_link, label: t("External Link")}
        ],
        label: t("Type")

      input :case_categories, :multi_select,
        options: &__MODULE__.get_categories/2,
        relation_key: :category_id,
        relation: :category,
        resetable: true,
        wrapped_labels: true,
        label: t("Categories")

      input :title, :text, label: t("Title")
      input :slug, :slug, source: :title, show_url: true, label: t("Slug")

      input :introduction, :rich_text,
        label: t("Intro text"),
        instructions:
          t("A short introduction of the case. ")

      input :listing_image, :image,
        label: t("Listing image"),
        instructions: t("Automatically cropped to 4/5")
    end
  end
end
```

* Omit fields you don’t want editors to change.  
* Group related fields with fieldsets for usability.  
* Use the widget types Brando provides (`:image`, `:textarea`, custom tag selector, etc.).


---

## Internationalization (`Brando.I18n`)

Brando uses Gettext for static translations.

### Gettext domains

The docs recommend separate domains:

```bash
mix gettext.extract --merge priv/gettext/frontend --locale no
mix gettext.extract --merge priv/gettext/backend --locale no
```

Keep **frontend** (site) and **backend** (admin) translations separate.

---

## Query Helpers (`Brando.Query`)

### TODO

---

## Static‑Site Generation & Sitemaps

### `Brando.SSG`

* `mix brando.ssg.build` (or similar) outputs static HTML for each route.  

### `Brando.Sitemap`

* Generates `sitemap.xml` from blueprint content.  
* Update whenever URLs change; exclude drafts & admin URLs.  
* Submit in robots.txt or Search Console.

########### OPENAI END