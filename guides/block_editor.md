# Block editor

Blocks are Brando's structured content system: editors compose entries from
**modules** (predefined templates with editable refs and vars), organized in
**containers**, reusable across **fragments**. This guide covers wiring blocks
into a schema, how the pieces fit, and how the editor manages state (useful
when debugging).

For exporting modules to editable Elixir DSL and importing changes back, see
[Module definitions as files](module_definitions.md).

## Terminology

"Module" here means a reusable block definition, not an Elixir module:

- **Module** (`Brando.Content.Module`, table `content_modules`) — the
  definition: template, refs and vars. Edited under Configuration → Modules.
- **Block** (`Brando.Content.Block`) — one instance in an entry. A block with
  `type: :module` renders the module named by its `module_id`.
- **Multi module** — a module with `multi: true` whose template renders child
  blocks. Each child is a block with `type: :module_entry`; these are distinct
  from blocks nested inside a container.
- **Module set** (`Brando.Content.ModuleSet`) — a named subset of modules that
  a `blocks` form field offers via `module_set:`.

Names such as `datasource_module`, `parser_module` and `Brando.Type.Module`
refer to actual Elixir modules.

<!-- usage-rules:start -->

## Wiring blocks into a blueprint

Add `trait :blocks`, a `:blocks` relation and a `blocks` declaration in the
form:

```elixir
trait :blocks

relations do
  relation :blocks, :has_many, module: :blocks
end

forms do
  form do
    blocks :blocks
    # ... tabs/fieldsets for regular fields
  end
end
```

This generates the join schema (`MyApp.Pages.Page.Blocks`), the
`entry_blocks` association and a `rendered_blocks`/`rendered_blocks_at` pair
on the entry. Multiple block fields per schema are supported — each gets its
own relation, form declaration and rendered fields. Without `trait :blocks`
a `blocks` declaration fails to compile.

Form options (passed via `blocks/2` opts):

- `module_set:` — restrict the module picker to a named set (default `"all"`).

## Rendering on the frontend

Blocks are rendered to HTML at save time and stored on the entry:

```heex
<Brando.HTML.render_blocks entry={@entry} />
<!-- or for a custom field name: -->
<Brando.HTML.render_blocks entry={@entry} field={:sections} />
```

`render_blocks/1` reads `entry.rendered_<field>` — no parsing at request
time. To parse at request time instead (e.g. for blocks containing
runtime-dynamic content), use `Brando.Villain.parse(entry.entry_blocks, entry)`
or the `render_data/1` component.

The HTML itself comes from your project's parser module, where each block
type's markup can be overridden — see the [Villain parser](villain_parser.md)
guide.

<!-- usage-rules:end -->

<!-- usage-rules:start -->

## Modules, refs and vars

A **module** (`Brando.Content.Module`) can use either Liquex (`:liquid`) or
HEEx (`:heex`) templates. In Liquex:

- **refs** — named slots holding a block primitive (header, text, picture,
  file, video, gallery, map, …). Templates reference them as `{% ref refs.name %}`.
- **vars** — typed variables (`text`, `string`, `color`, `select`, `boolean`,
  `image`, `file`, `video`, `gallery`, `link`, …) referenced bare by key:
  `style="color: {{ text_color }}"`.
- **multi modules** — a module whose template contains `{{ content }}`
  renders nested child blocks there (each an instance of a child module).

The equivalent HEEx forms are:

```heex
<article data-language={@language}>
  <h2>{@headline}</h2>
  <.ref block={@block} ref={:body} />
  <.content />
</article>
```

Vars are top-level assigns such as `@headline`. Renderer-owned assigns include
`@block`, `@refs`, `@entry`, `@identity`, `@configs`, `@links`, `@globals`,
`@navigation`, `@language`, `@locale`, `@request`, `@url`, `@entries`,
`@entries_with_meta`, `@content`, `@forloop` and `@render_context`. Var keys
that collide with these names are rejected.

<!-- usage-rules:end -->

Villain imports these HEEx components into module templates:

- `<.ref block={@block} ref={:name} />` renders an editable ref. Add `headless`
  and `:let={data}` to render the ref data yourself.
- `<.picture src={...} opts={[...]} />` and `<.video src={...} opts={[...]} />`
  render media.
- `<.entry_link var={@link_var} />` renders a link var; it also accepts a
  direct `href` or `entry` plus `field`.
- `<.route ... />`, `<.route_i18n ... />`, `<.fragment ... />` and `<.t ... />`
  provide the corresponding Villain helpers.
- `<.content />` inserts rendered children in multi modules and containers.
- `<.editable_field entry={@entry} field={:title} />` and `<.editable …>`
  make an entry field editable in [frontend edit mode](frontend_edit.md#entry-fields);
  in Liquex, `{% editable_field entry.title %}` and
  `{% editable entry.cover %}…{% endeditable %}`.

HEEx uses normal Elixir expressions, comprehensions and conditionals in place
of Liquex filters and control-flow tags. Parent and child modules may use
different template types, which supports gradual migration.

> #### HEEx templates are trusted code {: .warning}
>
> HEEx module templates compile and execute as server-side Elixir; they are not
> sandboxed like Liquex. Only trusted administrators should be allowed to edit
> module or container templates.

**Containers** (`Brando.Content.Container`) wrap root blocks in a palette-
aware `<section>` wrapper (using `{{ content }}` in Liquex or `<.content />` in
HEEx).
**Fragments** embed another entry's blocks by reference.

Modules are managed in the admin under Configuration → Modules; entries
reference them by id, so template edits apply everywhere on next render.

<!-- usage-rules:start -->

### Liquid tags and context

A Liquex template sees its vars by key, its refs as `refs`, and the render
context: `entry`, `language`, `identity` (`{{ identity.name }}`), `globals`
(`{{ globals.<set key>.<global key> }}`), `navigation`
(`navigation.<menu key>.<language>`), `configs`, and `links` (the identity's
links by lowercased name, `{{ links.instagram.url }}`). A module with a
datasource also gets `entries` (see [Datasources](datasources.md)).

Besides `{% ref %}` and `{% headless_ref %}`:

```liquid
{% picture entry.cover { sizes: 'auto', lazyload: true } %}
{% video entry.video { autoplay: true } %}
{% link cta %}
{% fragment partials footer en %}
{% route_i18n entry.language page_path show { entry.uri } %}
{% t en 'Read more' %}{% t no 'Les mer' %}
{% form contact %}
```

- `{% fragment %}` takes the fragment's parent key, key and language as bare
  words, not a quoted path.
- `{% t %}` outputs its string only when the entry's language matches.
- `{% link %}` renders an `<a class="link">` from a link var.
- `{% route %}` and `{% route_i18n %}` call your router's path helpers;
  `page_path` is never localized.
- Filters are Brando's (`media_url`, `i18n`, `json_ld`, `date`, `markdown`,
  `src`, …) plus any `name(value, args…, context)` function you add to
  `MyAppWeb.Villain.Filters` (generated by `mix brando.install`), which wins
  over Brando's of the same name.
- A Liquex container template's `{{ content }}` is replaced literally: write
  it exactly so, with single spaces.

<!-- usage-rules:end -->

## Named block regions

A **Blocks** ref (`:blocks` in [module definitions](module_definitions.md))
gives an ordinary module a named insertion point for its own collection of
module blocks, such as a sidebar. Name the ref (for example `sidebar`), set its
**Module set** (`"all"` by default) and use its description as the label
editors see. Place it with the normal ref syntax:

```liquid
<article>
  {% ref refs.text %}
  <aside>{% ref refs.sidebar %}</aside>
</article>
```

```heex
<article>
  <.ref block={@block} ref={:text} />
  <aside><.ref block={@block} ref={:sidebar} /></aside>
</article>
```

In the editor the region opens a drawer (**Content / Block region**) with its
own block list, sorting and module picker, limited to the configured set. The
content is saved with the entry. It lives in an internal `:slot` block under
the owning block, matched by the ref's name, so replacing or resetting the ref
row does not replace its content. The region renders its active children
without a wrapper; override `blocks/2` in your parser to change that (see the
[Villain parser](villain_parser.md) guide).

Renaming or removing a region ref keeps its content but stops rendering it. The
owning block lists such collections under **Unused content**, where they can be
opened, remapped to an empty current region on the same block, or deleted.

## Footnotes

Footnotes are off by default. Each note is a small collection of ordinary
modules from a configured module set, attached to a specific text ref or
Blueprint rich-text field. When enabled, the text editor gets a footnote button
that inserts a reference and opens the note's drawer. Tiptap stores only a
stable note UID; numbers are derived at render time.

**Text refs.** In the module's text ref configuration, switch **Footnotes** on
and set **Footnote module set** (default `"Footnotes"`); in module definitions
these are the `footnotes` and `footnote_module_set` fields. Put a text module
first in that set: it becomes the initial block of a new note. Switching
footnotes off hides the button but keeps existing references and notes.

**Blueprint rich-text fields.** Declare a dedicated blocks relation and opt the
top-level input in:

```elixir
relations do
  relation :body_notes, :has_many, module: :blocks
end

forms do
  form do
    tab "Content" do
      fieldset do
        input :body, :rich_text,
          footnotes: [blocks: :body_notes, module_set: "Footnotes"]
      end
    end
  end
end
```

The form mounts the notes editor itself; do not also declare
`blocks :body_notes`. `enabled: false` in the footnote options stops new notes
while keeping existing ones. Footnotes in subform inputs raise at compile time.
Render the field with its notes (preload the `entry_body_notes` block trees
first):

```heex
<Brando.HTML.render_rich_text entry={@entry} field={:body} />
```

`Brando.Villain.Footnotes.render_field/3` returns `%{html:, notes:}` for a
custom layout; `Footnotes.to_html/2` and `Footnotes.outlet/2` build the endnote
list.

**Numbering.** `Brando.Villain.parse/3` numbers references after rendering the
whole block field, so the sequence follows rendered order across blocks, and
appends a `section.footnotes` endnote list with backlinks. Pass
`footnote_scope: "article-#{entry.id}"` when several block fields share a page,
or `footnotes: false` to skip this step. Unreferenced notes are not rendered;
the editor lists them under **Unused content**, with **Restore reference**.
Footnote rendering uses Floki at runtime, so don't restrict Floki to
`only: :test` in the consuming app.

## Live preview

With a `preview_target` configured for the schema (see the Live Preview
guide), the editor renders block changes into the preview iframe as you
type — block-level diffs are morphed in place; structural changes and media
swaps reload the preview.

## How the editor manages state (debugging notes)

The admin editor follows a **single-owner** architecture (see also the
brando-blocks skill, `.claude/skills/brando-blocks/SKILL.md`, if you're working
on Brando itself):

- Each block is a live_component that owns its editing state exclusively.
  Parent re-renders never overwrite a mounted block's form.
- The `BlockField` component owns order, nesting and a uid-keyed **param-diff
  store** (`BrandoAdmin.Components.Form.BlockField.Ops` — a pure reducer).
  Blocks emit small named ops at every commit point; forms never travel
  between components.
- Save, live preview and share all **materialize** entry changesets from the
  diff store in one pass. Sequence always derives from list order; untouched
  blocks produce empty updates (no SQL).
- After a save, mounted blocks are re-seeded with freshly persisted data
  (`replace_form` cascade) so continued editing diffs against real db ids.
- Multi-user editing ships op snapshots over PubSub; a receiving editor's
  save cannot clobber another editor's shipped changes.
- On reconnect after a disconnect, unsaved blocks are restored from a
  sessionStorage capture (the server-side store dies with the LiveView
  process).

Practical implications:

- If a block's content "looks saved" but is missing after reload, check the
  op store path: the handler that changed the form must go through
  `Block.assign_block_form/2` (or `Block.commit_ref_data/2` for media
  commits). A form assigned directly never reaches the store.
- `BlockField rejected block op` log errors mean the op state and the UI
  state disagree — report them; they are never expected in normal operation.
