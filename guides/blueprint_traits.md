# Traits

<!-- usage-rules:start -->

A trait adds a capability to a Blueprint: fields, changeset steps, save
hooks, and the admin features that come with them. Declare traits at the top
of the Blueprint body:

<!-- usage-rules:no-compile -->
```elixir
trait :creator
trait :status
trait :sequenced, append: true
trait :soft_delete, obfuscated_fields: [:slug]
trait :timestamped
trait :translatable
trait :blocks
trait MyApp.Trait.Searchable, ranking: :weighted
```

`trait` takes a built-in trait's shorthand atom or a module, and options.
Write the options as literals; they are read when the Blueprint compiles. The
built-in shorthands are `:blocks`, `:blocks_prevent_circular_references`,
`:cast_polymorphic_embeds`, `:creator`, `:ensure_uid`, `:focal`, `:meta`,
`:module_versioned`, `:password`, `:permalink`, `:protect_password`,
`:protect_role`, `:revisioned`, `:scheduled_publishing`, `:sequenced`,
`:soft_delete`, `:status`, `:timestamped`, `:translatable`,
`:validate_var_keys` and `:watch_language`. `:villain` still resolves but is
deprecated; use `:blocks`.

The shorthand and the module, `trait Brando.Trait.Status`, register the same
trait. The shorthand also keeps the Blueprint from compiling against the
trait's runtime module, so prefer it.

<!-- usage-rules:end -->

To ask a schema about its traits:

* `has_trait/1` takes the module, or the underscored last part of its name:
  `Article.has_trait(Brando.Trait.Sequenced)` and
  `Article.has_trait(:sequenced)` are equivalent. For
  `Brando.Trait.Blocks.PreventCircularReferences`, the atom is
  `:prevent_circular_references`.
* `__trait__/1` takes the module and returns the options it was declared
  with, or `false`: `Article.__trait__(Brando.Trait.Sequenced)` returns
  `[append: true]`.
* `__traits__/0` lists every `{module, options}`.

## Built-in traits

<!-- usage-rules:start -->

### Status

`trait :status` adds `attribute :status, :status, required: true`. The status
is `:draft`, `:pending`, `:published` or `:disabled` (shown as
"Deactivated"). Context queries filter on it with `status:`; see
[Querying](querying.md#status-language-and-soft-deletion).

In the admin, listings get status buttons and a status menu on each row. The
form gets no status input by itself: add `input :status, :status`. Drafts are
validated more loosely; see [Drafts](blueprints.md#drafts). See
[Content status, deletion, and ordering](content_lifecycle.md).

<!-- usage-rules:end -->

### Timestamped

`trait :timestamped` adds `inserted_at` and `updated_at`, through Ecto's
`timestamps()`, so their type is `:naive_datetime`.

### Creator

`trait :creator` adds `relation :creator, :belongs_to`, `relation
:updated_by, :belongs_to` (both to `Brando.Users.User`) and `attribute
:edited_at, :datetime`. The changeset sets `creator` on insert, and
`updated_by` and `edited_at` when a user changes the entry. Saves made as
`:system`, and saves that only change `rendered_*` columns, leave them alone.

* `required:`: whether every entry needs a creator. Default `true`. An
  insert made as `:system` must then set `creator_id` itself.
* `derived:`: fields a pipeline writes on the user's behalf, such as image
  sizes. A save changing only those is not an edit.

Listings show a creator and last-editor column.

### Sequenced

`trait :sequenced` adds `attribute :sequence, :integer, default: 0`, for a
manual order that editors set by dragging rows. New entries get sequence 0
unless an option says otherwise:

* `append: true`: a new entry goes last, after the highest sequence.
* `strict: true`: a new entry goes first and the others move down by one.
  It takes precedence over `append`.

With a `language` field, both count within the entry's language. The
generated `changeset/5` sets the sequence when it is given one, which is how
`cast_assoc` orders sequenced children. Listings and subforms of sequenced
schemas can be reordered by dragging; see
[Choose sequence behavior](content_lifecycle.md#choose-sequence-behavior).

### Soft delete

`trait :soft_delete` adds `attribute :deleted_at, :datetime`. Deleting through
the context sets `deleted_at` instead of removing the row, and queries leave
deleted entries out unless they ask for them with `with_deleted:`.

`obfuscated_fields:` lists fields changed on deletion to free their values,
such as a unique slug, and restored on undelete:

```elixir
trait :soft_delete, obfuscated_fields: [:slug]
```

With `trait :status` too, listings show a **Deleted** status with the trash
and an **Undelete** action. See
[Deletion and restoration](content_lifecycle.md#deletion-and-restoration).

### Translatable

`trait :translatable` adds `attribute :language, :language` and, unless
`alternates: false`, the `alternates` relation and an `Alternate` join schema
that links an entry to its translations.

* `mode:`: `:independent` (the default), where each language version is
  edited on its own, or `:synchronized`, where one source entry controls the
  others.
* `source_controlled_fields:` and `language_controlled_fields:`: for
  synchronized mode, which fields follow the source and which assets each
  language chooses.
* `alternates:`: whether translations are linked. Default `true`; synchronized
  mode needs it.
* `runtime_config:`: read the options from application config at runtime.

The options are checked after the Blueprint compiles. Listings show the
editor's content language and offer duplicate-to-language actions; the form
gets a languages drawer. See [Languages and translations](i18n.md) for both
modes.

### Meta

`trait :meta` adds `meta_title` and `meta_description` (`:text`) and a
`meta_image` image asset. The form edits them in a **Meta** drawer, along with
`meta_canonical_url`, an optional [canonical override](meta.md#canonical-url).
It also adds `content_modified_at`, which only substantive edits move: read it
with `Brando.Blueprint.Value.modified_at/1` for JSON-LD
[`dateModified`](jsonld.md#datemodified) and the sitemap's `lastmod`. `ai:`
configures their [AI generation](blueprint_forms.md#ai-generated-values):

```elixir
trait :meta,
  ai: [meta_title: [prompt: "Write an SEO title from the title", context: [:title]]]
```

See [Page metadata](meta.md) and [Content SEO](content_seo.md).

### Blocks

`trait :blocks` marks a schema with [block fields](blueprint_fields.md#block-relations).
It adds no fields. It is needed for block preloads, for `blocks` editors in
the form, for footnotes, and for the **Re-render** listing action.

### Revisioned

`trait :revisioned` stores a revision on each save through the context and
adds a **History** drawer to the form. See [Revisions](revisions.md).

### Scheduled publishing

`trait :scheduled_publishing` adds `attribute :publish_at, :datetime` and
`attribute :unpublish_at, :datetime`. An entry with status `:pending` and a
`publish_at` is published at that time, a published one with an
`unpublish_at` is deactivated then, and the form gets a scheduling drawer
with both. An entry published without a `publish_at` gets the time it was
saved, whether the admin form, the context or a job saved it. See
[Scheduled publishing](scheduled_publishing.md).

### Permalink redirects

Add `trait :permalink` to a Blueprint with an
[`absolute_url`](blueprints.md#absolute-url) to offer redirects when editors
change an existing entry's key, slug or URL:

```elixir
trait :permalink
absolute_url ~H"/articles/{@entry.slug}"
```

After a successful save in the admin form, Brando compares the previous and
saved URLs and shows the proposed permanent (301) redirect. The editor can
create it or continue without it; either completes the chosen save action.
New entries, unchanged URLs, and entries without a URL (a page with
`has_url: false`, or any entry an `absolute_url ..., only:` declaration
excludes) do not prompt. Brando's pages include this trait.

When the URL changes, any exact redirect on the new URL is removed from the
saved entry's language before the prompt appears. This also happens when the
editor chooses **Continue without redirect**, closes the prompt, or renames
back to a previous URL. Pattern rules that may cover other pages are kept.

Confirmed redirects are stored in the previous language's SEO settings and
match the exact old path, so changing `/about` does not redirect
`/about/team`. The language must already have SEO settings. If creating the
redirect fails, the saved entry stays, and the editor can retry or continue
without it. See [Identity, SEO settings, and redirects](identity_and_seo.md#add-a-manual-redirect).

### Other built-in traits

These serve Brando's own schemas, and are available to applications:

* `:ensure_uid`: puts a generated `uid` when the field is empty. The schema
  declares `uid`.
* `:cast_polymorphic_embeds`: casts the schema's `PolymorphicEmbed`
  attributes.
* `:password`: on update, ignores an empty `password`, and hashes a changed
  password with Bcrypt when the entry is written. Pass the plain text, through
  the admin form or the context; validations see the plain text. Code that
  inserts a struct without a changeset hashes the password itself.
* `:protect_password` and `:protect_role`: refuse password and role changes
  the current user may not make.
* `:focal`: marks an image for reprocessing when its focal point changes.
* `:module_versioned`: increments a module's `version` when its definition
  changes.
* `:validate_var_keys`: validates the keys of a module's variables.
* `:blocks_prevent_circular_references`: stops a fragment from including
  itself.
* `:watch_language`: does nothing yet.

<!-- usage-rules:start -->

## When trait hooks run

A trait acts at three points:

* **Compile time**: it adds attributes, relations and assets to the
  Blueprint, and its options are validated after the module compiles.
* **Changeset**: its `changeset_mutator` runs in every `changeset/5` call,
  before or after `validate_required` depending on the trait.
* **Admin save**: `before_save/2` and `after_save/3` run when the admin form
  saves an entry, and when a revision or proposal is applied. Saves through
  the context's `create_*` and `update_*` functions do not call them.

<!-- usage-rules:end -->

Use the save hooks only for work that belongs to editing in the admin. Work
that every save needs belongs in `changeset_mutator`, deferred to the write
with `Ecto.Changeset.prepare_changes/2` so form validation, which never
writes, does not run it:

```elixir
@impl true
def changeset_mutator(_schema, _config, changeset, _user, _opts) do
  Ecto.Changeset.prepare_changes(changeset, &stamp/1)
end
```

`trait :password` hashes passwords and `trait :scheduled_publishing` fills
`publish_at` this way.

## Custom traits

```elixir
defmodule MyApp.Trait.Stamped do
  use Brando.Trait

  @changeset_phase :before_validate_required

  @impl true
  def generate_code(_schema, _opts) do
    quote do
      attributes do
        attribute :stamped_at, :datetime
      end
    end
  end

  @impl true
  def changeset_mutator(_schema, _config, changeset, :system, _opts), do: changeset

  def changeset_mutator(_schema, _config, changeset, _user, _opts) do
    Ecto.Changeset.put_change(changeset, :stamped_at, DateTime.utc_now(:second))
  end
end
```

```elixir
trait MyApp.Trait.Stamped
```

`use Brando.Trait` provides defaults for every callback. Override the ones
the trait needs:

* `generate_code(schema, opts)`: returns quoted code inserted into the
  Blueprint where `trait` is declared, usually `attributes`, `relations` or
  `assets` blocks, or functions. `opts` is the options as written.
* `changeset_mutator(schema, config, changeset, user, opts)`: changes the
  changeset. `config` is the trait's options as a map, and `opts` the options
  given to `changeset/5`. The default returns the changeset unchanged; once you
  define your own clauses, add a catch-all yourself.
* `validate(schema, opts)`: checks the Blueprint after it compiles. Return
  `true` or `:ok`, or raise.
* `before_save(changeset, user)` and `after_save(entry, changeset, user)`:
  save hooks, run as described above.
* `ai_field_opts(schema, config, field)`: AI options for a field, as
  `trait :meta` provides.

`@changeset_phase :before_validate_required` runs the mutator before required
fields are validated, for a trait that fills a required field. The default
is `:after_validate_required`.

Each Blueprint using the trait implements a protocol named
`<Trait>.Implemented`, so `MyApp.Trait.Stamped.list_implementations()` lists
the schemas that use it.

### Keeping trait compilation small

The Blueprint calls `generate_code/2` while it compiles, so it compiles
against the trait module. A trait with heavy runtime code can move
`generate_code/2` to a small compiler module and name it at each use with
`compile_with:`:

```elixir
defmodule MyApp.Trait.Searchable.Compiler do
  def generate_code(_schema, _opts) do
    quote do
      attributes do
        attribute :search_text, :string
      end
    end
  end
end

defmodule MyApp.Trait.Searchable do
  use Brando.Trait

  @impl true
  defdelegate generate_code(schema, opts), to: MyApp.Trait.Searchable.Compiler

  # runtime callbacks and helpers stay here
end
```

```elixir
trait MyApp.Trait.Searchable,
  compile_with: MyApp.Trait.Searchable.Compiler,
  ranking: :weighted
```

The compiler must export `generate_code/2`; the trait's own is then not
called. `compile_with:` is not part of the trait's options. A trait that adds
no fields can use `compile_with: Brando.Trait.NoopCompiler`. Brando's built-in
traits choose their compilers themselves.
