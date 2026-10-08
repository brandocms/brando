# Blueprint forms

A Blueprint's `forms` section describes the admin form for its entries: the
tabs, the fieldsets in them, and an input for each field. A form LiveView
renders it with `BrandoAdmin.Components.Form`, which loads the entry, builds
the changeset with the Blueprint's `changeset/5`, and saves through the
context.

Field declarations are in [Attributes, relations, and assets](blueprint_fields.md);
recipes for media inputs are in [Images, files, and galleries](media.md).

<!-- usage-rules:start -->

## A complete example

```elixir
forms do
  form do
    default_params %{"status" => "draft"}
    blocks :blocks

    tab t("Content") do
      alert :info, t("The title and slug are shown in listings and links.")

      fieldset do
        size :half
        input :status, :status
        input :title, :text, label: t("Title")
        input :slug, :slug, source: :title, show_url: true, label: t("Slug")
        input :section, :radios,
          label: t("Section"),
          options: [
            %{label: t("News"), value: :news},
            %{label: t("Essays"), value: :essays}
          ]
        input :external_url, :text, label: t("External URL"), show_if: {:section, :news}
      end

      fieldset do
        size :half
        shaded true
        input :cover, :image, label: t("Cover")
        input :category_id, :select,
          label: t("Category"),
          options: &__MODULE__.category_options/2,
          resetable: true
      end
    end

    tab t("Links") do
      fieldset do
        inputs_for :links do
          label t("Links")
          cardinality :many
          style :inline
          default &__MODULE__.default_link/2

          input :title, :text, label: t("Title", MyApp.Articles.Link)
          input :url, :text, label: t("URL", MyApp.Articles.Link)
        end
      end
    end
  end
end

def category_options(_form, _opts), do: MyApp.Articles.list_categories!(%{order: "asc name"})
def default_link(_entry, _asset), do: %{}
```

<!-- usage-rules:end -->

<!-- usage-rules:start -->

## The form LiveView

```elixir
defmodule MyAppAdmin.Articles.ArticleFormLive do
  use BrandoAdmin.LiveView.Form, schema: MyApp.Articles.Article

  alias BrandoAdmin.Components.Form

  def render(assigns) do
    ~H"""
    <.live_component
      module={Form}
      id="article_form"
      entry_id={@entry_id}
      current_user={@current_user}
      presences={@presences}
      schema={@schema}
    />
    """
  end
end
```

`use BrandoAdmin.LiveView.Form` takes `schema:` (required) and
`skip_image_hooks:` (a boolean, default `false`). It assigns `@schema`,
`@entry_id` (from the route's `entry_id` param, `nil` on create),
`@current_user` and `@presences`, and sets up presence, locking and sync for
the entry.

<!-- usage-rules:end -->

Give `BrandoAdmin.Components.Form`:

* `id`: always `"<singular>_form"`, such as `"article_form"`. Inputs and
  subforms send updates to the form by this id.
* `schema`, `entry_id`, `current_user` and `presences`.
* `name`: the [named form](#named-forms) to render. Default `:default`.
* `initial_params`: params for a new entry. When given and not empty, they
  replace the form's `default_params`.
* `layout`: `:entry` (default) heads the form with the entry's title, a
  breadcrumb with the content type and language, and the status control
  beside the title; Save and close sits in the toolbar. A new entry is headed
  "New" and the blueprint's singular name. Where "new" must agree with the
  noun, translate the msgid `"New %{type}"` in the blueprint's own Gettext
  domain (`projects_project.po`: `msgstr "Nytt %{type}"`); the blueprint's
  wording replaces the default. `:settings` is for a
  singleton settings screen: the form renders no heading (put a
  `Workspace.header` above it), shows its tabs as plain pill tabs, and saves
  in place from a sticky bar at the bottom.
* slots: the optional `:instructions` and `:footer`. A `:header` slot from
  earlier versions is accepted and not shown.

## The form

```elixir
forms do
  form do
    default_params %{"status" => "draft"}
    query %{preload: [:category, :cover]}
    after_save &__MODULE__.notify_editors/2
    redirect_on_save &__MODULE__.after_save_path/3
    # tabs and blocks
  end
end
```

A `form` takes an optional name and these options:

* `default_params`: params cast into a new entry when the form opens on
  create. Use one kind of key throughout, all strings or all atoms; Ecto
  rejects a map that mixes them.
* `query`: how an existing entry is loaded. See
  [Loading the entry](#loading-the-entry).
* `after_save`: a function called with the saved entry and the current user
  after every save from this form. Its return value is ignored. It runs after
  the traits' `after_save/3` callbacks and does not run for saves made
  elsewhere, such as through the context.
* `redirect_on_save`: a function called with the socket, the saved entry and
  `:create` or `:update`. It returns the path to navigate to after **Save and
  close**. Without it, that button returns to the listing. **Save and
  continue** and **Save and create new** do not use it.

`query`, `after_save` and `redirect_on_save` accept a function capture or a
`{module, function, extra_args}` tuple. The runtime arguments come first and
`extra_args` are appended, so `{MyApp.Articles, :notify, [:editors]}` calls
`MyApp.Articles.notify(entry, user, :editors)`.

### Loading the entry

Without `query`, the form loads the entry with `%{matches: %{id: id}}` and
preloads every relation, asset and block field the Blueprint declares
(`Brando.Blueprint.preloads_for/1`).

A static map adds options to that query. Brando puts the entry ID into its
`:matches`, which must itself be a map when given:

```elixir
query %{preload: [:category, :cover, :links, project_gallery: [gallery_objects: :image]]}
```

A function receives the ID and returns the whole query, for loading that
depends on it:

```elixir
query &__MODULE__.form_query/1

def form_query(id), do: %{matches: %{id: id}, preload: [:category, :cover]}
```

<!-- usage-rules:start -->

With either form, the automatic preloads are off: list every association the
form shows, including asset fields, galleries and `alternate_entries` for
translatable schemas. The ID is the route parameter, a string, until a new
entry is first saved. Brando always adds `with_deleted: true`, so a
soft-deleted entry can still be opened.

<!-- usage-rules:end -->

### Named forms

A Blueprint can declare more than one form, for example a short form for a
different workflow:

```elixir
forms do
  form do
    # the full form
  end

  form :password do
    tab t("Password") do
      fieldset do
        input :password, :password, label: t("Password"), confirmation: true
      end
    end
  end
end
```

The form component renders the one named in its `name` attribute:
`<.live_component module={Form} name={:password} ... />`. A missing name
raises when the form mounts. Form names must be unique.

## Tabs, alerts, and fieldsets

A form holds tabs; a tab holds alerts and fieldsets; a fieldset holds inputs
and subforms.

### Tabs

```elixir
tab t("Content") do
  # alerts and fieldsets
end
```

`tab` takes a name, shown on the tab button and translated through the
Blueprint's Gettext domain. The first tab opens first. When a save fails, the
form switches to the tab of the first field with an error. The error summary
names fields by their input's `label` (or the humanized field name), and
errors on a foreign key such as `cover_id` belong to the `cover` input.

### Alerts

```elixir
alert :info, t("The title and slug are shown in listings and links.")
alert :warning, &__MODULE__.quota_notice/1
alert :warning, {MyAppAdmin.FormAlerts, :quota_notice, [limit: 10]}
alert :warning, t("Templates look this fragment up by its key."), show_if: &__MODULE__.key_changed?/1
```

`alert` takes a type (`:info`, `:warning` or `:error`) and the content: a
string, translated like other labels, or a one-arity function component, as
a capture or an MFA tuple. The component receives `form`, `schema`,
`current_user`, `form_cid` and `form_id`.

`show_if:` takes a one-arity function. It receives the form and the alert
shows while it returns `true`, such as a warning that appears once an editor
starts changing something risky. An exception in it hides the alert.

A tab's alerts render above its fieldsets, wherever they are declared.
Alerts belong in tabs only, not in fieldsets.

### Fieldsets

```elixir
fieldset do
  label t("Publishing")
  size :half
  shaded true
  input :status, :status
end
```

Fieldset options are written inside the block:

* `size`: `:full` (the default), `:half` or `:third`. `:quarter` is accepted
  but has no styling and renders full width.
* `align`: `:start` (the default) or `:end`, which aligns the fieldset to
  the bottom of the row. `:center` is accepted and does nothing.
* `shaded`: a grey background. Default `false`.
* `style`: `:regular` (the default) or `:inline`, which places the inputs
  side by side.
* `label`: a section heading, translated.
* `superuser`: `true` renders the fieldset only for users with the
  `:superuser` role, for technical settings editors have no use for. Other
  users do not get it at all, so its inputs are not submitted.
* `component`: a one-arity function component rendered above the inputs,
  such as an SEO preview. It receives `form`, `fieldset`, `relations`,
  `current_user`, `form_cid`, `form_id` and `id`, and renders read-only
  content; it does not own form state.

## Inputs

```elixir
input :title, :text, label: t("Title"), instructions: t("Shown in listings")
```

<!-- usage-rules:start -->

`input` takes the field name, a type, and options. The name must be a schema
field, a virtual field, an association or an embed of the Blueprint, and
appear once in the form.

<!-- usage-rules:end -->

### Common options

Every input type reads these:

* `label`: the label, translated through the Blueprint's Gettext domain.
  Without it the humanized field name is used; `label: :hidden` hides it.
* `instructions`: help text under the input, translated.
* `placeholder`: placeholder text, translated, for inputs that show one.
* `disabled`: `true` disables the input. `:unless_superuser` disables it for
  everyone but superusers (top-level inputs only).
* `readonly`: `true` makes `:text`, `:number` and `:rich_text` inputs read
  only. Like `disabled`, it takes `:unless_superuser`.
* `monospace`: a monospace font, for keys and codes.
* `class`: extra classes on the input's wrapper.
* `debounce`: milliseconds between keystrokes and validation. Default 300.
* `size`: the input's width inside its fieldset: `:full` (default), `:half`
  or `:third`.
* `hidden` and `show_if`: see [Showing a field depending on
  another](#showing-a-field-depending-on-another).

<!-- usage-rules:start -->

Options are not checked when the Blueprint compiles; a misspelled option is
ignored.

<!-- usage-rules:end -->

### Showing a field depending on another

<!-- usage-rules:start -->

`show_if:` shows an input only while another field has one of the given
values. `hidden:` does the opposite, and also takes `true` or a function:

* `show_if: {:kind, :url}` or `show_if: {:kind, [:url, :email]}`;
* `hidden: {:kind, :pdf}` or `hidden: {:kind, [:pdf, :audio]}`;
* `hidden: true`, which never shows the input;
* `hidden: &__MODULE__.hide_quote?/1`, which receives the form and hides the
  input while it returns `true`.

<!-- usage-rules:end -->

```elixir
input :kind, :radios, options: [%{label: t("Web link"), value: :url}, %{label: t("PDF"), value: :pdf}]
input :url, :text, show_if: {:kind, :url}
input :file, :file, show_if: {:kind, [:pdf, :audio]}
```

<!-- usage-rules:start -->

Atoms and strings compare equal, so `{:kind, :url}` matches the param
`"url"`; other values must match exactly, so `{:count, 1}` does not match the
param `"1"`. The field in a tuple is checked when the Blueprint compiles.
`show_if` takes tuples only; a function there is ignored and the input always
shows. Use `hidden:` for a function.

<!-- usage-rules:end -->

The rules work the same in top-level fieldsets, subform rows and transformer
entries, where the field is one of the row's own. A hidden input is not
rendered, so it submits nothing and the entry keeps its current value. For a
value that must be submitted without being shown, use the `:hidden` input
type.

### Text and numbers

* `:text`: a single line. Reads `readonly` and [`ai`](#ai-generated-values).
* `:textarea`: several lines. `rows:` sets the height (default 3). Reads
  `ai`.
* `:number`: a number field. Reads `readonly`.
* `:email`: an email field.
* `:phone`: a text field for phone numbers.
* `:password`: never shows the stored value. `confirmation: true` adds a
  second field, `<name>_confirmation`, for the changeset's
  `confirmation` constraint.
* `:code`: a code editor for source text such as HTML or Liquid.
* `:string_list`: a list of short strings edited one per row, for an
  attribute using `Brando.Type.StringList`.
* `:disclosed_text`: shows "Label: value" and opens a text field on click,
  for values that rarely change.
* `:hidden`: a hidden input. `:hidden_i18n` does the same for each language
  of an `:i18n_string` field.

### Slugs

```elixir
input :slug, :slug, source: :title, show_url: true
```

`:slug` fills itself from another field while editors type, until they edit
the slug themselves on a new entry:

* `source`: the field, or list of fields, to build the slug from. The
  fields are checked when the Blueprint compiles.
* `camel_case: true`: builds `camelCase` instead of `kebab-case`.
* `show_url: true`: shows the entry's [absolute URL](blueprints.md#absolute-url)
  under the field.
* `prefix`: a string, or a function of the form's changeset, put in front of
  the generated slug. Pages use it to start a child page's URI with its
  parent's.

`from:` passes the compile-time check but is not read by the input; use
`source:`.

### Choices

* `:toggle`: an on/off switch for a boolean. `compact: true` makes it smaller.
* `:checkbox`: a checkbox. `text:` sets the text beside it.
* `:status`: the four statuses (draft, pending, published, deactivated) as
  radio buttons, or as a dropdown with `compact: true`. Use it with
  `trait :status`.
* `:radios`: one radio button per option. See [Options](#options).
* `:select` and `:multi_select`: see below.
* `:color`: a color picker. `picker: false` hides the free picker,
  `palette_id:` offers the colors of a palette, and `opacity: true` allows
  transparency. `default:` sets the color of a new entry.
* `:date` and `:datetime`: date and date-time pickers. `default:` takes a
  value or a zero-arity function for an empty field.

### Options

<!-- usage-rules:start -->

`:radios`, `:select` and `:multi_select` take `options:`:

* a list of `%{label: ..., value: ...}` maps. Labels are translated through
  the Blueprint's Gettext domain, so use `t/1`;
* a list of entries, labelled by their identifiers and valued by their IDs;
* `:languages` or `:admin_languages`, for the configured content or admin
  languages;
* a function receiving the form and the input's options, returning one of
  the lists above:

```elixir
input :category_id, :select, options: &__MODULE__.category_options/2

def category_options(_form, _opts), do: MyApp.Articles.list_categories!(%{order: "asc name"})
```

Options are maps or entries; `{label, value}` tuples are not supported in
forms.

<!-- usage-rules:end -->

Select and multi-select cache their options. A function runs when the input
mounts, when the picker opens, and on an explicit refresh, not on every
change. When its options depend on other fields, list them in
`options_depends_on:` so the options also reload when those values change:

```elixir
input :parent_id, :select,
  options: &__MODULE__.parent_options/2,
  options_depends_on: [:id, :language]
```

Radios have no cache: their function runs whenever the input renders, so
keep it to a constant list or one built from config, not a query.

### Select

```elixir
input :client_id, :select,
  label: t("Client"),
  options: &__MODULE__.client_options/2,
  update_relation: {:client, &__MODULE__.get_client/1},
  resetable: true
```

`:select` picks one value in a dialog. It reads:

* `options` and `options_depends_on`, as above;
* `resetable: true`: a button that sets the value to `nil`;
* `filter`: a search field over the options. Default `true`;
* `narrow`: a narrower dialog;
* `inline`: the options inline instead of in a dialog;
* `allow_custom: true`: also accepts a value typed by the editor;
* `update_relation: {relation, fetcher}`: for a `belongs_to` foreign key,
  the fetcher receives the chosen ID and returns `{:ok, entry}`, which is put
  on the relation so the form shows it without a reload. The relation must
  declare `module:`. It works on top-level inputs only.

### Multi-select

```elixir
input :article_categories, :multi_select,
  label: t("Categories"),
  options: &__MODULE__.category_options/2,
  relation_key: :category_id,
  relation: :category,
  resetable: true
```

<!-- usage-rules:start -->

`:multi_select` picks several values. It works with two kinds of field:

* an array attribute, such as `{:array, :string}`, storing the chosen values;
* a `has_many` relation to a join schema, storing one join entry per choice.
  Set `relation_key:` to the join schema's foreign key and `relation:` to its
  association to the chosen schema. The join schema needs
  `@allow_mark_as_deleted true`, and the relation `cast: true`.

To let editors reorder the chosen entries, give the join schema
`trait :sequenced` and the relation `sort_param:` and `drop_param:`.
`many_to_many`, `belongs_to`, `has_one` and embedded fields are not
supported; use a join schema.

<!-- usage-rules:end -->

It also reads `options_depends_on`, `resetable`, `filter`, `narrow` and
`wrapped_labels: true` (labels wrap instead of being cut off). `form: {Module,
:form_name}` adds a **Create** button that creates a new entry of `Module`
with that form.

### Related entries

```elixir
input :related_entries, :entries,
  label: t("Related"),
  sources: [
    {MyApp.Articles.Article, %{status: :published, order: "asc title"}},
    {Brando.Pages.Page, %{}}
  ]
```

`:entries` is the input for an `:entries` relation: a list of entries of any
Blueprint with persisted identifiers. `sources:` (required) lists the
schemas editors can pick from, each with the list options used to load the
choices. `filter_language: true` offers only entries in the same language as
the entry being edited. The relation's `constraints: [max_length: n]` and
`min_length` limit how many can be picked.

### Media

* `:image`, `:video` and `:file` edit an asset of that type. `editable:
  false` shows the asset without letting editors change it. `:video` also
  takes `defaults:`, a map of video fields new videos start with.
* `:gallery` edits a gallery asset. `layout: :grid` shows thumbnails in a
  grid instead of a list.

See [Images, files, and galleries](media.md) and [Videos](videos.md).

### Translated strings

`:i18n_text` and `:i18n_textarea` edit an `:i18n_string` attribute with one
tab per language. They offer the admin languages by default;
`languages: :content` offers the site's content languages. `:i18n_textarea`
takes `rows:`. See [Translated strings in one field](i18n.md#translated-strings-in-one-field).

### Links

`:link` edits a link (URL, entry or file) stored as a `Brando.Content.Var`.
Brando's menu items use it through a `has_one` relation whose foreign key,
`menu_item_id`, is a column of Brando's vars table. The vars table has no
column for a site's own schemas, so a site Blueprint stores a link as a URL
attribute or an `:entries` relation instead.

### Custom input components

A type can also be a component of your own:

```elixir
input :rating, {:live_component, MyAppAdmin.Inputs.Rating}
input :swatch, &MyAppAdmin.Inputs.swatch/1
```

A LiveComponent receives `field`, `label`, `instructions`, `placeholder`,
`opts`, `current_user`, `form_id`, `on_change` and `path`, among others. A
function component receives the field and options as given; pass them
through `prepare_input_component/1` from the BrandoAdmin.Utils module to resolve labels and
instructions like the built-in inputs.

An atom type names a built-in input. An unknown atom is not caught when the
Blueprint compiles; the form fails when it renders.

## Rich text

```elixir
input :introduction, :rich_text,
  extensions: ["p", "h2", "bold", "italic", "list", "orderedList", "link"],
  styles: [
    %{element: "p", class: "lede", label: "Introduction"},
    %{element: "span", class: "small-caps", label: "Small caps"}
  ],
  label_mode: "compact"
```

`:rich_text` stores HTML. Configure its tools and named styles on the input;
existing markup stays readable when a tool is turned off.

Omitted `extensions`, `nil` and `["all"]` use the default tools: `p`, `h1` to
`h4`, `list`, `orderedList`, `link`, `button`, `bold`, `italic`, `sub`,
`sup`, `color`, `unsetMarks`, `jumpAnchor`, `smartText` and `align`. An
explicit `[]` means no optional formatting tools. `"list"` enables bullets
and `"orderedList"` numbering; Tab and Shift-Tab indent and outdent where
applicable. `"blockquote"` is opt-in and in no preset. The legacy
`"action_button"` is read as `"button"`.

The module reference editor offers **Basic**, **Caption** and **Article**
presets next to the individual controls. A preset adds tools to the current
selection and never removes any. The same union is available as
`Brando.Blueprint.Forms.RichText.add_preset(extensions, :article)`.

A style is identified by its element and class, not its label. Internal
extension keys never enter stored HTML. `label_mode` sets how the paragraph
menu is labelled: `"compact"` (the default, `¶` / `H2`), `"icon"` or
`"full"`. Removing `"smartText"` disables typography substitutions;
`typography: [emDash: false]` turns single ones off. `readonly: true` or
`disabled: true` prevents editing.

Content links keep their target's identifier alongside the URL. When the
target's URL changes, Brando updates the link in block text and ordinary
rich-text fields and re-renders the owners; the link text stays as written.
The link dialog also takes external and relative URLs, page anchors, button
appearance, new-tab behaviour and nofollow. Unsafe destinations are refused.
Pasting keeps supported formatting and turns the rest into text.

Alt-F10 focuses the toolbar, arrow keys move between its controls, and Escape
closes the current menu or the expanded editor. The expanded editor edits the
same document with the same undo history; its **Done** returns to the form,
and the form's save button saves the entry.

### Footnotes

```elixir
relations do
  relation :introduction_notes, :has_many, module: :blocks
end

forms do
  form do
    tab t("Content") do
      fieldset do
        input :introduction, :rich_text,
          footnotes: [blocks: :introduction_notes, module_set: "Footnotes"]
      end
    end
  end
end
```

`footnotes:` lets editors attach notes to a rich-text field. `blocks` names a
block relation that stores the notes, and `module_set` the module set notes
are written with; `enabled: false` keeps the configuration but turns the
feature off. The relation must not also have its own `blocks` editor, the
schema needs `trait :blocks`, and footnotes work only on top-level inputs, not
in subforms. See [Footnotes](block_editor.md#footnotes).

## AI-generated values

`ai:` on a `:text`, `:textarea` or `:rich_text` input lets editors generate
its value:

```elixir
input :meta_description, :textarea,
  ai: [
    prompt: "Write a succinct meta description based on title and intro",
    context: [:title, :intro, :blocks]
  ]
```

* `prompt` (required): the instruction.
* `context`: fields sent with the prompt. `:blocks` sends the rendered block
  content, including unsaved changes.
* `model`: a `"provider:model"` spec or a name from the `models:` config.
* `api_key`: a key for this field.
* `temperature`, `max_tokens`, `top_p`, `presence_penalty`,
  `frequency_penalty`, `tool_choice`, `tools`, `system_prompt`,
  `provider_options`, `receive_timeout` and `thinking_timeout` are passed to
  the model.

On `:text` and `:textarea`, a button generates a value and replaces the
field's. A `:rich_text` toolbar offers **Write with AI** instead: Rewrite,
Shorten or Continue the selection. The result shows as a coloured
suggestion; Accept inserts it and Discard leaves the document unchanged, and
one Undo reverses an accepted suggestion. Suggestions are left out of saved
HTML, recovery copies and the preview until accepted, and a response does not
overwrite text edited while it was being generated. The editor inserts plain
text and paragraphs, so write rich-text prompts for plain prose rather than
HTML or Markdown.

The button shows only when `Brando.AI` is configured, and only on top-level
inputs, not in subforms. An input's `ai:` options are used as they are,
without merging the `fields:` config below.

```elixir
config :brando, Brando.AI,
  enabled: true,
  models: [
    default: "openai:gpt-4o-mini",
    image: "openai:gpt-4o-mini"
  ],
  providers: [
    openai: [api_key: System.get_env("OPENAI_API_KEY")]
  ],
  fields: [
    block_text: [prompt: "Help refine this passage while preserving its meaning"]
  ],
  default_opts: [temperature: 0.4]
```

`models:` names the models a site uses: `:default` for everything, and a name
per kind of job (alt text asks for `:image`) that falls back to `:default`.
`default_model: "..."` is still read, as `models: [default: "..."]`.
`fields:` holds defaults by field name: `block_text` turns on the same
suggestions for text in the block editor, and the meta fields below read
theirs from here when the Blueprint gives none. Model and provider settings
and credentials stay on the server.

`meta_title` and `meta_description` from `trait :meta` are edited in the
form's Meta drawer, not in a tab. Configure their generation on the trait:

```elixir
trait :meta,
  ai: [
    meta_title: [prompt: "Write an SEO title from the title", context: [:title]],
    meta_description: [prompt: "Write an SEO description", context: [:title, :blocks]]
  ]
```

or with a hidden input, whose options the drawer reuses:

```elixir
input :meta_description, :textarea,
  hidden: true,
  ai: [prompt: "Write a succinct meta description", context: [:title, :blocks]]
```

<!-- usage-rules:start -->

## Block editors

```elixir
relations do
  relation :blocks, :has_many, module: :blocks
end

forms do
  form do
    blocks :blocks, module_set: "Articles", template_namespace: "articles"
    # tabs
  end
end
```

`blocks` adds a block editor for a block relation. It is declared on the
form, not in a tab, and renders below the tabs. The schema needs
`trait :blocks`, and the name must be a `has_many` relation with
`module: :blocks`. Options:

* `module_set`: offer only the modules of this set. A site can set it in
  config instead, per schema and field:
  `config :brando, MyApp.Articles.Article, module_sets: [blocks: "Articles"]`.
  Without either, every module is offered.
* `template_namespace`: an empty editor offers the content templates of this
  namespace to start from. Without it, the namespace named after the schema
  is used. See `Brando.Content.StartingTemplates`.
* `starts_with`: module classes an empty editor offers first. See
  [Starting modules](blueprint_fields.md#starting-modules).
* `hidden`: as for inputs: `true`, `{field, value}` or a function of the
  form. A hidden editor stays mounted.

`label` and `palette_namespace` are accepted and not used. See the
[Block editor](block_editor.md) guide.

<!-- usage-rules:end -->

## Subforms

`inputs_for` edits a relation or embed in place: one nested form for a
`belongs_to`, `has_one` or `embeds_one`, and a list of them for a `has_many`,
`embeds_many` or `many_to_many`.

```elixir
inputs_for :links do
  label t("Links")
  instructions t("Shown below the article")
  cardinality :many
  style :inline
  default &__MODULE__.default_link/2

  input :title, :text, label: t("Title", MyApp.Articles.Link)
  input :url, :text, label: t("URL", MyApp.Articles.Link)
end
```

Write the options inside the block. `inputs_for :links, label: "Links" do`
calls a deprecated three-argument macro that prints a warning and drops the
whole subform.

* `cardinality`: `:one` (the default) or `:many`. It must match the
  relation: `:many` for `has_many`, `embeds_many`, `many_to_many` and
  `entries`; `:one` for `belongs_to`, `has_one` and `embeds_one`.
* `style`: `:regular` (the default), `:inline`, `:listing`, or
  `{:transformer, fields}`. See below.
* `default`: the entry **Add entry** creates: a map, a struct, or a
  function receiving the parent entry and `nil`. Give one for `:many`
  subforms: without it, **Add entry** adds `nil` instead of an entry and the
  form fails. Prefer a function or a
  map to a `%Struct{}` literal of another Blueprint: a literal makes this
  Blueprint compile against that one, which can close a compile-time cycle.
* `label` and `instructions`: shown above the subform, translated through
  the parent Blueprint's domain. With `cardinality :one` they are also the
  fallback label of every input in it.
* `add_entry: false`: hides the **Add entry** button while keeping editing,
  ordering and removal.
* `listing`, `layout` and `listing_context`: see the styles below.
* `component`: a custom renderer, see [Custom subform
  components](#custom-subform-components).
* `size` is accepted and ignored.

The inputs inside take the related schema's field names and are checked
against that schema. Their labels are translated in the parent's Gettext
domain; name the related schema, as in `t("Title", MyApp.Articles.Link)`, to
use its domain instead. A subform contains only `input`s: subforms do not
nest and cannot hold block editors.

For `:many` subforms, new rows are cast through the relation, so the relation
needs `cast: true` (embeds are always cast). Rows can be dragged into order
when the related schema has `trait :sequenced` or the relation is an
`embeds_many`. The parameter names for ordering and removal come from the
relation's `sort_param:` and `drop_param:`, and default to
`sort_<name>_ids` and `drop_<name>_ids`.

What a subform input cannot do: generate with `ai:`, use `update_relation:`
on a select, take `:unless_superuser`, or carry footnotes.

<!-- usage-rules:start -->

### Rules

* Write subform options inside the `inputs_for` block; `inputs_for :links,
  label: "Links" do` drops the whole subform.
* `cardinality :many` for `has_many`, `embeds_many`, `many_to_many` and
  `entries`; `:one` (the default) for `belongs_to`, `has_one` and
  `embeds_one`.
* A `:many` subform needs a `default`, and its relation needs `cast: true`
  unless it is an embed.
* A subform holds only `input`s: no nested subforms and no block editors.

<!-- usage-rules:end -->

### Regular and inline

`style :regular` shows each entry as a complete form with its own remove
button. `style :inline` with `cardinality :many` shows a table, one row per
entry and one column per input, headed by the input labels; `:hidden` inputs
get no column. Media inputs in an inline row are compact.

### Listing style

For longer collections, `style :listing` shows each entry as a one-line
summary with an **Edit** button:

```elixir
inputs_for :prices do
  cardinality :many
  style :listing
  listing &__MODULE__.price_summary/1
  default &__MODULE__.default_price/2

  input :title, :text, label: t("Title")
  input :price, :text, label: t("Price")
end

def price_summary(assigns) do
  ~H"""
  <strong>{@entry.title || "New price"}</strong>
  <small>{@entry.price || "Set a price"}</small>
  """
end
```

The `listing` function component receives `@entry`, with pending changes
applied. Keep the summary short: what tells this entry from its neighbours.
New entries open for editing, and validation errors open the entries that
have them. A collapsed entry keeps its fields in the form, so unsaved values
are still submitted. **Done** collapses the editor; save the parent form to
store the changes. `style :listing` needs `cardinality :many`, a `listing`
function, and no `component`.

### Transformers

A transformer turns uploaded or picked images and videos into entries of a
related Blueprint, one entry per file, for collections where each entry
carries media, such as a project's clients with their logos:

```elixir
inputs_for :clients do
  label t("Clients")
  cardinality :many
  style {:transformer, :logo}
  default &__MODULE__.default_client/2
  listing &__MODULE__.client_listing/1

  input :logo, :image
  input :name, :text, label: t("Name", MyApp.Projects.Client)
end

def default_client(_project, _image), do: %{}

def client_listing(assigns) do
  ~H"""
  <div>{@entry.name}</div>
  """
end
```

`style {:transformer, field}` names an image or video asset of the related
Blueprint; `{:transformer, [:image, :video]}` takes one image and one video
field for mixed media. The relation must be a `has_many` or `embeds_many` to
another Blueprint, and the subform needs `cardinality :many`.

Files can be dropped anywhere on the transformer or picked with its buttons.
A batch is ordered by filename and every file gets a placeholder entry at
once, so entries appear in a predictable order. `default` builds each new
entry: a map, a struct, or a function receiving the parent entry and the
uploaded asset (`nil` when adding an empty entry). Without it, each entry
starts as an empty struct of the related schema.

* `listing`: a summary component. It receives `@entry` (the related struct
  with its assets), `@dom_id` and `@target`. A button can change a field in
  place with `BrandoAdmin.Components.Form.Transformer.set_field(@target,
  @dom_id, :size, :large)`. Without `listing`, every entry shows its fields
  directly.
* `layout`: `:list` (the default), rows; or `:grid`, cards with the media on
  top. `:grid` needs `listing`; without it entries show as a list.
* `listing_context: true`: the listing also gets `@index` (from 0) and
  `@entries`, and every entry re-renders when one changes. Leave it off
  unless the summary depends on its neighbours.
* `add_entry: false`: removes **Add entry**, for schemas where an entry
  without media is never valid.

Expanding an entry offers a picker for each of its asset fields, so media can
be swapped or removed without uploading again.

### Custom subform components

```elixir
inputs_for :vars do
  label t("Variables")
  component :vars
end
```

`component` replaces the built-in subform with a LiveComponent. Brando's own
are available as tokens: `:vars`, `:page_vars`, `:gallery_objects`,
`:identity_type_config`, `:image_focal` and `:form_fields`. Tokens keep the
Blueprint from compiling against the admin component tree. Any other value
must be a module. The component receives `field`, `subform`, `label`,
`instructions`, `placeholder`, `current_user`, `form_cid` and `form_id`. The
cardinality check is skipped for subforms with a component.

## How traits change the form

* `trait :meta`: a **Meta** button and drawer with `meta_title`,
  `meta_description` and `meta_image`.
* `trait :revisioned`: a **History** button with the revisions drawer.
* `trait :scheduled_publishing`: a drawer to set `publish_at`.
* `trait :translatable`: on saved entries with alternates, a languages drawer
  linking the translations. In synchronized mode, a translation panel and
  locked source-controlled fields. When creating an entry in a
  multi-language site with no `:language` input, a notice names the language
  it is created in.
* `trait :blocks`: required for `blocks` editors and footnotes.
* `trait :sequenced` on a related schema: drag handles in its subform.
* `trait :creator`: saves from the form record the editor and edit time.

`trait :status` adds no input; declare `input :status, :status`. A
[live preview](live_preview.md) configured for the schema adds preview and
share buttons.

## Compile-time checks

Form declarations are checked after the Blueprint and the schemas it refers
to have compiled. A mistake is reported as a **compile warning**, naming the
form and field, and the module still compiles. Build with `mix compile
--warnings-as-errors` so these stop the build. The checks:

* a static `query`'s `:matches` is a map;
* top-level inputs and subforms name schema fields, and each appears once;
* `hidden:` and `show_if:` tuples, and `source:`/`from:` options, name schema
  fields;
* `inputs_for` names a relation whose module is a loaded Ecto schema, its
  `cardinality` matches the relation, and its inputs name fields of the
  related schema;
* `style :listing` has `cardinality :many`, a `listing` and no `component`;
* transformers target a `has_many` or `embeds_many` relation to a Blueprint,
  and name existing image and video assets, at most one of each;
* `blocks` names a `has_many` relation with `module: :blocks`, on a schema
  with `trait :blocks`.

Input types, input options, and whether an input type suits its field are
not checked. Footnote configuration errors raise when the Blueprint compiles.
