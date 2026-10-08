# Attributes, relations, and assets

<!-- llms-description: Attributes, relations and assets: field types and options, uniqueness, constraints and media fields. -->

A Blueprint's fields come from three sections. `attributes` declares columns,
`relations` declares associations and embeds, and `assets` declares images,
files, videos and galleries. Each becomes an Ecto field or association, takes
part in the generated `changeset/5`, and goes into the
[migration snapshot](blueprint_migrations.md) when it is stored.

<!-- usage-rules:start -->

```elixir
attributes do
  attribute :title, :string, required: true
  attribute :slug, :slug, required: true, unique: [prevent_collision: true]
  attribute :price, :decimal, precision: 10, scale: 2
end

relations do
  relation :category, :belongs_to, module: MyApp.Catalog.Category, required: true
  relation :variants, :has_many, module: MyApp.Catalog.Variant, cast: true, on_replace: :delete
end

assets do
  asset :cover, :image, cfg: :default
end
```

Each section may appear more than once; traits use that to add fields. A
field name may be declared once across all three. After changing stored
fields, generate a migration as described in
[Blueprint migrations](blueprint_migrations.md).

<!-- usage-rules:end -->

## Attributes

```elixir
attribute :name, type, options
```

### Types

* `:string` and `:text`: text, both stored as a `text` column. `:text`
  is a hint that the value is long; Ecto treats both as `:string`.
* `:slug`: a string meant for URLs. It is cast like a string and does not
  slugify itself; the form's [`:slug` input](blueprint_forms.md#slugs)
  builds the value. Slug fields are listed by `__slug_fields__/0` and are
  adjusted when entries are duplicated.
* `:integer`, `:float`, `:decimal`, `:boolean`, `:map`, `:id`, `:date`,
  `:time` and `:naive_datetime`: the Ecto types of the same name.
* `:datetime`: Ecto's `:utc_datetime`.
* `:timestamp`: Ecto's `:naive_datetime`, for older schemas.
* `:uuid`: `Ecto.UUID`.
* `:status`: the publishing status, stored as an integer: `:draft`,
  `:published`, `:pending` and `:disabled`. Usually added by
  [`trait :status`](blueprint_traits.md#status).
* `:enum`: `Ecto.Enum` with the `values:` option. See [Enums](#enums).
* `:language`: the entry's language, an `Ecto.Enum` of the configured
  languages. See [Languages](#languages).
* `:i18n_string`: one short text per language in a single `jsonb` field.
  See [Translated strings](#translated-strings).
* `{:array, type}`: an array of `:string`, `:integer`, `:id`, `:map`, `:enum`
  or `Ecto.Enum`. A bare `:array` is rejected; always give the element type.
* A module: an `Ecto.Type` or `Ecto.ParameterizedType`, such as
  `Brando.Type.StringList` or `PolymorphicEmbed`. The migration uses the
  type's primitive storage type.

`:file` is in the type list but its Ecto type does not exist, so it does not
compile; use a [file asset](#assets).

### Options

* `required: true`: the changeset validates that the field is present.
  [Drafts](blueprints.md#drafts) skip this for fields the identifier does not
  show. It does not add `NOT NULL` to the database; use `null: false` for
  that. Default `false`.
* `default:`: the value of a new struct, and the column default in the
  generated migration. The migration stores the default as the Ecto type
  dumps it, so `default: :low` on an integer enum becomes `1`.
* `null: false`: a `NOT NULL` column. Migration only.
* `precision:` and `scale:`: for `:decimal` columns. `scale` needs
  `precision` and must not exceed it. Migration only.
* `source:`: the physical column, when it differs from the field name. Forms,
  changesets and queries use the field name; migrations, indexes and
  constraints use the source. See
  [Physical Ecto sources](blueprint_migrations.md#physical-ecto-sources).
* `rename_from:`: the field's previous name, so the next migration renames
  the column instead of dropping it. See
  [Renaming an attribute](blueprint_migrations.md#renaming-an-attribute).
* `virtual: true`: a field that is cast and validated but not stored. A
  virtual field cannot take `null`, `precision`, `scale`, `source`,
  `rename_from` or `unique`.
* `unique:`: see [Uniqueness](#uniqueness).
* `constraints:`: see [Constraints](#constraints).
* Ecto's `autogenerate`, `read_after_writes`, `load_in_query`, `redact`,
  `skip_default_validation` and `writable` are passed to the schema field and
  left out of the migration.

Unknown options fail the compilation. Custom parameterized types are the
exception: their options are passed to the type unchecked. Use the root
[`primary_key`](blueprints.md#schema-settings) declaration rather than
`primary_key: true` on an attribute.

`:inserted_at` and `:updated_at` declared as attributes, which
[`trait :timestamped`](blueprint_traits.md#timestamped) does, become Ecto's
`timestamps()` and take no options.

<!-- usage-rules:start -->

### Rules

* Attribute types: `:string`, `:text`, `:slug`, `:integer`, `:float`,
  `:decimal`, `:boolean`, `:map`, `:id`, `:date`, `:time`, `:datetime` (UTC),
  `:naive_datetime`, `:uuid`, `:status`, `:enum`, `:language`, `:i18n_string`,
  `{:array, type}`, or an `Ecto.Type` module. A bare `:array` is rejected, and
  `:file` does not compile; use a [file asset](#assets).
* A `:slug` attribute does not slugify itself; the form's
  [`:slug` input](blueprint_forms.md#slugs) builds the value.
* `required: true` validates presence in the changeset only; add `null: false`
  for a `NOT NULL` column.
* `default:` is both the new struct's value and the column default.
* Unknown options fail the compilation. Declare the primary key with the root
  `primary_key` declaration, not `primary_key: true` on an attribute.

### Enums

```elixir
attribute :visibility, :enum, values: [:public, :private], default: :private
attribute :priority, :enum, values: [low: 1, high: 2], default: :low
attribute :formats, {:array, :enum}, values: [:jpg, :png], default: [:jpg]
```

`values:` is required and non-empty, with unique values: a list of atoms, a
keyword list of atoms to strings, or a keyword list of atoms to integers. The
first two are stored as text, the third as an integer. `embed_as:`
(`:values` or `:dumped`) is passed to `Ecto.Enum`. The application uses atoms;
the database stores what each atom maps to.

<!-- usage-rules:end -->

### Languages

```elixir
attribute :language, :language
```

A `:language` attribute is an `Ecto.Enum` of the site's languages, read from
the `:languages` config when the Blueprint compiles; changing the languages
needs a recompile. `languages:` gives the list explicitly, in the config's
format, `[[value: "en", text: "English"], ...]`. The attribute is always
required, whatever `required:` says, and the migration adds an index on it.
[`trait :translatable`](blueprint_traits.md#translatable) declares it for
you.

### Translated strings

```elixir
attribute :alt, :i18n_string
```

`:i18n_string` holds one short text per language, stored as `jsonb`: a map of
language code to text, through `Brando.Type.I18nString`. It suits text that
belongs to one record in every language rather than to a translated entry,
such as an image's alt text. A plain string is cast under the default
language, and all-blank values are stored as `nil`. Edit it with the
`:i18n_text` or `:i18n_textarea` input, and read one language with
`Brando.Type.I18nString.get(value, language)`, which falls back to the
default language. See [Languages and translations](i18n.md#translated-strings-in-one-field).

### Polymorphic embeds

A `PolymorphicEmbed` attribute is left out of the ordinary cast. Add
`trait :cast_polymorphic_embeds` to cast it.

### Reading configuration in declarations

Declarations are evaluated when the Blueprint compiles. When one needs
Brando's configuration, use `Brando.RuntimeConfig`, which reads it without
making the Blueprint compile against the application supervisor:

```elixir
attribute :language, :language, languages: Brando.RuntimeConfig.get(:admin_languages)
```

`Brando.config/1` works too.

<!-- usage-rules:start -->

## Uniqueness

`unique:` on an attribute adds a unique constraint to the changeset and a
unique index to the migration.

<!-- usage-rules:no-compile -->
```elixir
# Unique across the table
attribute :key, :string, unique: true

# Unique per language, with a custom message
attribute :slug, :slug, unique: [with: :language, message: "is already used in this language"]
```

The keyword form takes:

* `with:`: a field or list of fields that scope the uniqueness. They must be
  stored columns of the same Blueprint, distinct, and not the field itself.
* `message:`: the error message. Default `"has already been taken"`.
* `prevent_collision:`: see below.

A virtual field cannot be unique.

<!-- usage-rules:end -->

### Preventing collisions

`prevent_collision` makes the changeset change a taken value instead of
failing: it tries `value`, then `value-1`, `value-2` and so on up to
`value-29`, and adds an error after that. It works on string-like fields:
`:string`, `:text`, `:slug` and custom string types.

```elixir
# Unique across the table
attribute :slug, :slug, unique: [prevent_collision: true]

# Unique per language
attribute :slug, :slug, unique: [prevent_collision: :language]

# Unique within the scope a callback returns
attribute :slug, :slug,
  unique: [
    prevent_collision: &__MODULE__.slug_scope/1,
    with: :language,
    message: "is already used"
  ]

def slug_scope(changeset) do
  import Ecto.Query
  language = Ecto.Changeset.get_field(changeset, :language)
  from(entry in __MODULE__, where: entry.language == ^language)
end
```

* `true` checks the whole table, and only when the value changed.
* A field or list of fields checks among entries with the same values in
  them, and also when one of those fields changed. When a scope value is
  `nil`, nothing collides.
* A one-arity function receives the changeset and returns the query to look
  for collisions in. The collision check, the constraint and the index are
  scoped by the fields in `with:`; list there the columns the query filters
  on. Callback-only declarations are unique across the whole table in the
  database. When a `with:` field is `nil`, collision handling is skipped.

`prevent_collision: true` and the field forms take no other keys: no
`message` and no `with`. Only the function form combines with `with:` and
`message:`.

Collision handling skips the entry itself, soft-deleted entries (with
`trait :soft_delete`), invalid changesets, and drafts.

## Constraints

`constraints:` adds validations. Attributes take:

* `length:`, `min_length:`, `max_length:`: non-negative integers, checked
  with `validate_length/3` on strings and arrays.
* `format:`: a regex, checked with `validate_format/3`.
* `acceptance: true`: `validate_acceptance/2`, for a virtual "I accept"
  checkbox.
* `confirmation: true`: `validate_confirmation/2`, which compares the field
  with `<field>_confirmation`.

```elixir
attribute :title, :string, required: true, constraints: [max_length: 120]
attribute :email, :string, constraints: [format: ~r/@/]
```

Relations take `length`, `min_length` and `max_length` on collections
(`has_many`, `many_to_many`, `embeds_many` and `entries`), and block
relations take [`require_blocks`](#requiring-blocks). Attributes, relations
and assets all take the cross-field constraints below. Unknown keys and
malformed values fail the compilation. There is no numeric `min` or `max`;
validate ranges in a custom changeset or trait.

### Requiring one of several fields

`required: true` makes a single field mandatory. When an entry is valid with
either of two fields, such as a listing image or a listing video, neither can
be required on its own. Use `one_of`:

```elixir
assets do
  asset :listing_image, :image,
    constraints: [one_of: [:listing_image, :listing_video]],
    cfg: :default

  asset :listing_video, :video, cfg: :default
end
```

The error is added to the field carrying the constraint and to every field it
lists, with the message `"requires one of: <fields>"`, or `one_of_message:`.
Declare it on one of the fields and leave `required: true` off all of them.
An asset counts as present whether it was set as an association or as its
`_id` column. `nil`, `""`, `[]` and unloaded associations count as absent.

`exactly_one_of` is for alternatives rather than a fallback, such as a media
item holding an image or a video but never both:

```elixir
asset :image, :image,
  constraints: [
    exactly_one_of: [:image, :video],
    exactly_one_of_message: "requires either an image or a video"
  ],
  cfg: :default
```

### Database check constraints

A database check constraint is the real guarantee: a race between two
requests, or a direct `Repo.insert`, still reaches the database. Declare it
so a violation returns an invalid changeset instead of raising
`Ecto.ConstraintError`:

```elixir
asset :image, :image,
  constraints: [
    exactly_one_of: [:image, :video],
    check: [must_have_one_media_type: "requires either an image or a video"]
  ],
  cfg: :default
```

The name must match the database constraint exactly. `check:` also takes a
bare atom or a list of atoms, which use `check_message:`, or `"is invalid"`
when that is unset. Message overrides belong in the same `constraints:` list
as the constraint they are for.

## Relations

```elixir
relation :name, type, options
```

<!-- usage-rules:start -->

Every relation needs `module:`. The types:

* `:belongs_to`: a foreign key on this table.
* `:has_one` and `:has_many`: entries of another schema that point here.
* `:many_to_many`: entries linked through a join table.
* `:embeds_one` and `:embeds_many`: embedded schemas stored in a `jsonb`
  column, usually Blueprints with `data_layer :embedded`.
* `:entries`: a sorted list of entries of any Blueprint, picked with the
  [`:entries` input](blueprint_forms.md#related-entries).

Two special forms use `:has_many`:

* `relation :blocks, :has_many, module: :blocks`: a block field. See
  [Block relations](#block-relations).
* `relation :alternates, :has_many, module: :alternates`: translation links,
  added by `trait :translatable`. Don't declare it yourself.

<!-- usage-rules:end -->

### Belongs to

```elixir
relation :category, :belongs_to, module: MyApp.Catalog.Category, required: true
```

The foreign key, `<name>_id` unless `foreign_key:` says otherwise, is cast
with the other fields, so a form or API sets the relation by ID. `required:
true` validates the foreign key.

* `foreign_key:`: the foreign-key field. The same name is used for casting,
  validation, constraints and the migration.
* `references:`: the referenced column. Default `:id`.
* `type:`: the foreign key's type; `:binary_id` for UUID primary keys.
* `source:`: the physical column, when the field name differs.
* `null: false`: a `NOT NULL` column. Migration only.
* `on_delete:`: what the database does when the referenced row is deleted:
  `:nothing`, `:nilify_all`, `:delete_all`, `:restrict` or `:default_all`.
  Migration only. Without it, the migration uses `:nilify_all` for relations
  named `cover`, `image`, `avatar`, `meta_image` or `file`, `:delete_all` on
  join tables (two belongs-to relations and nothing else), and `:nothing`
  otherwise.
* `constraint_name:`: the foreign-key constraint's name.
* `unique:`: `true` or `[with: fields, message: "..."]`, as for attributes,
  without `prevent_collision`.
* `on_replace:`: Ecto's option, for `cast: true`.
* `primary_key: true`: part of the primary key, for join schemas with
  `primary_key false`. See [Relation option
  corrections](blueprint_migrations.md#relation-option-corrections).
* `cast:`: also cast the associated entry from nested params. `true` uses
  `cast_assoc` with the related schema's `changeset/2`; `:with_user` passes
  the current user too; `[with: {Module, :function}]` calls that function
  with the changeset and params, and `[with: {Module, :function, [with_user:
  true]}]` adds the user.
* `define_field: false`: declare the foreign key yourself as an attribute,
  for options `belongs_to` does not pass. `source`, `null` and
  `primary_key` then go on that attribute, not the relation:

```elixir
attributes do
  attribute :owner_id, :id, null: false
end

relations do
  relation :owner, :belongs_to,
    module: MyApp.Users.User,
    foreign_key: :owner_id,
    define_field: false,
    required: true
end
```

### Has one and has many

```elixir
relation :variants, :has_many,
  module: MyApp.Catalog.Variant,
  cast: true,
  on_replace: :delete,
  preload_order: [asc: :sequence]
```

<!-- usage-rules:start -->

A `has_one` or `has_many` is only cast with `cast: true`. Without it the
changeset ignores the relation's params, which is right when entries are
managed elsewhere. With it, `cast_assoc` calls the related schema's
changeset with the current user; for `has_many`, each entry's position
becomes its `sequence`. A form or API that sends an empty value (`nil`,
`""`, `[]`, `%{}` or a list of blank IDs) clears the collection.

<!-- usage-rules:end -->

* `required: true`: requires at least one entry, with `required_message:`.
  Needs `cast: true`.
* `foreign_key:` and `references:`: as in Ecto.
* `on_replace:` (`:delete`, `:delete_if_exists`, `:nilify`,
  `:mark_as_invalid`, `:raise`; `has_one` also `:update`) and `on_delete:`
  (`:nothing`, `:nilify_all`, `:delete_all`): Ecto's options. Subforms that
  remove entries need an `on_replace:` other than the default `:raise`.
* `preload_order:` (`has_many` only): the order of preloaded entries, a list
  of fields or `{direction, field}` tuples. A sequenced child schema without
  one is preloaded by `sequence`. `has_one` passes Brando's check but Ecto
  rejects it.
* `sort_param:` and `drop_param:` (`has_many`): the param names for ordering
  and removing entries, used by subforms and multi-selects.
* `where:` and `defaults:`: Ecto's options.
* `invalid_message:` and `force_update_on_change:`: passed to `cast_assoc`.
  Like `required_message:`, they need `cast: true`.
* `through: [:assoc, :assoc]`: an Ecto through association. `module:` is still
  required and is ignored. Through associations cannot be cast and take no
  `foreign_key`, `references`, `preload_order`, `on_replace`, `on_delete`,
  `where` or `defaults`; set those on the underlying associations.

### Many to many

```elixir
relation :tags, :many_to_many,
  module: MyApp.Catalog.Tag,
  join_through: "catalog_products_tags",
  on_replace: :delete,
  cast: true
```

`join_through:` (required) is a join schema module or a table name. With
`cast: true` the changeset takes a list of IDs (string or atom keys) and
loads the entries; IDs that do not resolve add a cast error. An empty value
clears the list. `join_keys:`, `join_where:`, `join_defaults:` (which needs a
join schema module), `where:`, `defaults:`, `preload_order:`, `on_replace:`
(`:delete`, `:mark_as_invalid`, `:raise`), `on_delete:` (`:nothing`,
`:delete_all`) and `unique: true` are Ecto's options. Here `unique` is Ecto's
duplicate check, not an index.

The [multi-select](blueprint_forms.md#multi-select) input does not support
`many_to_many`. For a picker, use a `has_many` to a join schema instead.

### Embeds

```elixir
relation :settings, :embeds_one, module: MyApp.Catalog.Settings
relation :links, :embeds_many, module: MyApp.Catalog.Link
```

Embeds are always cast with `cast_embed`, and take no `cast:`. The related
module's `changeset/2` is used; a Blueprint's generated changeset works.
`with:` names another function. `""` removes an `embeds_one` and empties an
`embeds_many`. `on_replace:` defaults to `:update` for `embeds_one` and
`:delete` for `embeds_many`. `source:`, `load_in_query:`,
`defaults_to_struct:` (`embeds_one`), `sort_param:` and `drop_param:`
(`embeds_many`), `required:` and the cast messages are also accepted.

### Entries

```elixir
relation :related_entries, :entries, constraints: [max_length: 3]
```

An `:entries` relation stores a sorted list of identifiers, so it can point
to entries of any Blueprint with persisted identifiers. Brando generates a
join schema, `<Schema>.<Name>Identifier`, and its table,
`<table>_<name>_identifiers`; a `module:` you give is replaced. Use
`constraints:` to limit the count and the [`:entries`
input](blueprint_forms.md#related-entries) to edit it.

<!-- usage-rules:start -->

### Block relations

```elixir
trait :blocks

relations do
  relation :blocks, :has_many, module: :blocks
end
```

`module: :blocks` declares a block field. For a relation named `:blocks`,
Brando generates the join schema `<Schema>.Blocks` and table
`<table>_blocks`, the association `entry_blocks`, and the columns
`rendered_blocks` and `rendered_blocks_at`. There is no `blocks`
association; templates read the rendered HTML. A Blueprint can have several
block fields under different names. Blocks are cast by the block editor, not
by `cast:`; don't set it. Add `trait :blocks` and a
[`blocks` editor](blueprint_forms.md#block-editors). See
[Block editor](block_editor.md).

<!-- usage-rules:end -->

#### Requiring blocks

```elixir
relation :blocks, :has_many, module: :blocks, constraints: [require_blocks: ["header"]]
```

`require_blocks:` lists module classes the field must contain, active and not
deleted. It is checked when the blocks change, and not for drafts.

#### Starting modules

An empty block editor offers up to four modules to start with, under its
templates when it has any. They are the modules entries of the same kind
usually *start* with: the module of the first block, counted across the
field's entries in the entry's language, with "first 34/41" under
each. When the first block is a container, the container is counted with
its first module, and the tile inserts both. Free slots are filled with the
field's most used modules, without a count. With fewer than five entries
that have blocks, the editor offers the modules in the picker's order
instead. Only modules the field's module set allows are offered. The counts
are cached for five minutes. See `Brando.Content.StartingModules`.

A new site has nothing to count. Pin modules to the front with
`starts_with:` on the [`blocks` editor](blueprint_forms.md#block-editors),
listing module classes, as `require_blocks:` does:

```elixir
forms do
  form do
    blocks :blocks, starts_with: ["hero", "intro"]
  end
end
```

Pinned modules come first, in this order, followed by what the content
shows.

### Required collections

`required: true` on a cast `has_many`, `many_to_many` or `entries` rejects
`nil`, an empty string, list or map, and a list of only blank IDs, with
`required_message:` when given. Optional collections clear to an empty list.

### Preloads

`Brando.Blueprint.preloads_for(MyApp.Catalog.Product)` returns the preloads
for a complete entry: belongs-to, has-one and collection relations, assets
with their gallery objects, alternates, identifiers, and block fields with
`trait :blocks` (pass `skip_blocks: true` to leave them out). A cast
`has_many` honours its `preload_order`. The admin form
uses this list when it has no [custom query](blueprint_forms.md#loading-the-entry).

<!-- usage-rules:start -->

## Assets

```elixir
assets do
  asset :cover, :image, cfg: %{upload_path: "images/products/covers"}
  asset :brochure, :file, cfg: %{allowed_mimetypes: ["application/pdf"]}
  asset :clip, :video, cfg: :default
  asset :gallery, :gallery, cfg: :default
end
```

An asset is a `belongs_to` to Brando's media tables: `:image` to
`Brando.Images.Image`, `:file` to `Brando.Files.File`, `:video` to
`Brando.Videos.Video`, and `:gallery` to `Brando.Galleries.Gallery`. The
column is `<name>_id`, and the migration deletes with `:nilify_all`, so
deleting the media leaves the entry without it. Images, files and videos are
set by ID like a foreign key; galleries are cast with their objects.

<!-- usage-rules:end -->

Options:

* `cfg:` (required): the upload and processing configuration. See
  [Asset configuration](#asset-configuration).
* `required: true`: the asset must be present.
* `constraints:`: the [cross-field constraints](#requiring-one-of-several-fields).
* `alt_from:` (images): the entry field the site renders as this image's alt
  text, such as `:title` for an artwork. Images uploaded to the field are not
  counted as missing alt text in the image library, which labels them **Alt
  text from its entry**, or on the **Alt text** page. Brando does not copy the
  field into the image; templates render the entry field themselves.
* `required_message:`, `invalid_message:` and `force_update_on_change:`
  (galleries): passed to the gallery's `cast_assoc`. When a form clears a
  required gallery, `required_message` is used and the error keeps
  `validation: :required`.

Unknown options fail the compilation. For rendering and upload recipes, see
[Images, files, and galleries](media.md) and [Videos](videos.md).

<!-- usage-rules:start -->

### Asset configuration

`cfg:` takes:

* `:default`: the configured default for the type.
* A map or keyword list: merged over the default. See below.
* A config struct: `%Brando.Type.ImageConfig{}`, `%Brando.Type.FileConfig{}`
  or `%Brando.Type.VideoConfig{}`, used as it is.
* A zero-arity function capture, such as `&__MODULE__.cover_cfg/0`: called
  whenever the config is read and merged like a map. Use it for config that
  depends on runtime state.
* `:config_target` (files): the stored file's `config_target` decides.

<!-- usage-rules:end -->

The defaults come from `config :brando, Brando.Images, default_config: ...`
(and `Brando.Files`, `Brando.Videos`), or Brando's built-in defaults. Literal
configs are merged when the Blueprint compiles, so a changed default config
needs a recompile.

The fields, by type:

* All: `upload_path`, `allowed_mimetypes`, `size_limit` (bytes),
  `random_filename`, `slugify_filename`, `overwrite`, `cdn`,
  `completed_callback`, and `hidden_folder` (images and files).
* Images: `sizes`, `srcset`, `default_size` and `formats` (from `:original`,
  `:jpg`, `:png`, `:webp`, `:avif`, `:gif`).
* Files: `force_filename` and `content_disposition` (`:attachment` or
  `:inline`).
* Videos: `upload_strategy` (`:local`, `:s3`, `:mux`, `:bunny`,
  `:cloudflare`, `:vimeo` or `:none`; `nil` uses the configured default),
  `allow_uploads`, `allow_external_urls`, `force_filename` and `meta`
  (provider settings). See [Videos](videos.md).

Unknown fields fail the compilation, as do an empty `upload_path`, a
non-positive `size_limit`, empty MIME lists, unknown formats or strategies,
malformed sizes, and a `srcset` naming a size that does not exist. Function
configs are checked when they are first read.

<!-- usage-rules:start -->

An image config's `sizes` replaces the default sizes; name the
`{:standard, %{...}}` preset to extend them, as described in
[Images, files, and galleries](media.md#configure-a-cover-image). When the
replacement has no `srcset`, the default `srcset` is kept only if all its
sizes still exist.

```elixir
assets do
  asset :cover, :image,
    cfg: %{
      upload_path: "images/products/covers",
      default_size: "large",
      sizes: %{
        "thumb" => %{"size" => "400x400>", "crop" => true, "quality" => 80},
        "large" => %{"size" => "1400", "quality" => 80}
      },
      srcset: %{default: [{"thumb", "400w"}, {"large", "1400w"}]}
    }
end
```

<!-- usage-rules:end -->

A gallery takes `image:` and `video:` configs:

```elixir
asset :gallery, :gallery,
  cfg: %{
    image: %{upload_path: "images/products/gallery"},
    video: %{upload_path: "videos/products/gallery", upload_strategy: :local}
  }
```

A flat map without `image:` configures the images. Unlike an image asset, a
gallery merges its `sizes` into the default sizes, size by size, instead of
replacing them.

### Completion callbacks

```elixir
asset :brochure, :file, cfg: %{completed_callback: &__MODULE__.brochure_uploaded/2}
asset :clip, :video, cfg: %{completed_callback: {MyApp.Media, :video_ready, [notify: true]}}
```

`completed_callback` runs when an upload is done: when a file is stored,
when an image has been processed (SVG included), and when a video is stored
or first becomes ready at its provider. A function receives the asset and the
current user. An MFA receives those two and then its extra arguments, so the
second example calls `video_ready(video, user, {:notify, true})`. Processing
and provider webhooks can retry, so make callbacks idempotent; and don't
assume the editor has saved the entry that uses the asset yet.

### Config targets

Every uploaded media record stores a `config_target` naming the config it was
uploaded with, such as `"image:MyApp.Catalog.Product:cover"`, and Brando
reads that asset's `cfg` again when it processes or replaces the media. A
target written as `"image:MyApp.Catalog.Product:function:cover_cfg"` calls the
Blueprint's exported `cover_cfg/0` and normalizes its result. The schema must
be a loaded Blueprint and the field or function must exist; resolving a target
never creates atoms. When an upload's target does not resolve, the upload uses
the type's default config and stores the target as `"default"`.
