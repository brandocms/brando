# Block editor

Blocks are Brando's structured content system: editors compose entries from
**modules** (predefined templates with editable refs and vars), organized in
**containers**, reusable across **fragments**. This guide covers wiring blocks
into a schema, how the pieces fit, and how the editor manages state (useful
when debugging).

## Wiring blocks into a blueprint

Add a `:blocks` relation and a `blocks` declaration in the form:

```elixir
relations do
  relation :blocks, :has_many, module: :blocks
end

forms do
  form do
    blocks :blocks, label: "Blocks"
    # ... tabs/fieldsets for regular fields
  end
end
```

This generates the join schema (`MyApp.Pages.Page.Blocks`), the
`entry_blocks` association and a `rendered_blocks`/`rendered_blocks_at` pair
on the entry. Multiple block fields per schema are supported — each gets its
own relation, form declaration and rendered fields.

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

## Modules, refs and vars

A **module** (`Brando.Content.Module`) is a Liquid-ish template with:

- **refs** — named slots holding a block primitive (header, text, picture,
  file, video, gallery, map, …). Templates reference them as `{% ref refs.name %}`.
- **vars** — typed variables (`text`, `string`, `color`, `select`, `boolean`,
  `image`, `file`, `video`, `gallery`, `link`, …) referenced bare by key:
  `style="color: {{ text_color }}"`.
- **multi modules** — a module whose template contains `{{ content }}`
  renders nested child blocks there (each an instance of a child module).

**Containers** (`Brando.Content.Container`) wrap root blocks in a palette-
aware `<section>` wrapper (their template also uses `{{ content }}`).
**Fragments** embed another entry's blocks by reference.

Modules are managed in the admin under Configuration → Modules; entries
reference them by id, so template edits apply everywhere on next render.

## Live preview

With a `preview_target` configured for the schema (see the Live Preview
guide), the editor renders block changes into the preview iframe as you
type — block-level diffs are morphed in place; structural changes and media
swaps reload the preview.

## How the editor manages state (debugging notes)

The admin editor follows a **single-owner** architecture (see also the
"Block Editor" section in CLAUDE.md if you're working on Brando itself):

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
