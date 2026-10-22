# Footnotes and block regions

<!-- llms-description: Footnotes on text refs and rich-text fields, and named block regions in module templates: configuration, rendering and numbering, unused content, and limits. -->

A module can hold more blocks than its own refs. A **block region** is a named
place in a module template where editors add blocks of their own, such as a
sidebar. A **footnote** is a note attached to a text ref or a Blueprint
rich-text field; each note holds ordinary modules, so it can carry text, an
image, a video or a download. Both are stored as part of the entry's block tree
and saved with the entry.

## Block regions

Add a **Blocks** ref to the module, give it a stable name such as `sidebar`,
and set its **Module set** (`"all"` by default). Its description is the label
editors see, such as "Further reading". Place it in the module template with the
normal ref syntax:

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

In the editor the region opens a drawer with its own block list, sorting and
module picker, limited to the configured set. The region renders its active
blocks without a wrapper. To change that, override `blocks/2` in your parser;
see the [Villain parser](villain_parser.md) guide.

The content belongs to the owning block and is matched to the ref by name.
Replacing or resetting the ref row keeps the content. Renaming or removing the
ref keeps it too, but it no longer renders; see [Unused content](#unused-content).

## Footnotes

Footnotes are off by default and are enabled per text ref or per rich-text
field. When enabled, the text editor's toolbar gets a footnote button. It
inserts a reference at the cursor and opens the note's drawer, which uses the
block editor's module picker, media fields and ordering. The text stores only
the note's UID; numbers are worked out when the text renders, in the order the
references appear.

Notes come from a module set. Put a text module first in that set: a new note
starts with it. Add image, video and download modules to offer media in notes.

### On a text ref

In the module's text ref, switch **Footnotes** on and set **Footnote module
set** (default `"Footnotes"`). In [module definition files](module_definitions.md)
these are the ref's `footnotes` and `footnote_module_set` fields.

Switching footnotes off hides the button. Existing references and notes still
render and can still be edited. Only the module definition enables footnotes;
an editor cannot turn them on from the entry.

### On a Blueprint rich-text field

Declare a dedicated blocks relation for the notes and name it in the input's
`footnotes:` option:

```elixir
trait :blocks

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

The options are:

- `blocks:` (required): the blocks relation that stores the field's notes.
- `module_set:` (required): the title of the module set notes use.
- `enabled:` (default `true`): `false` stops editors adding notes. Existing
  notes still render and can still be edited.

The form mounts the notes editor itself; do not also declare
`blocks :body_notes`, which raises at compile time. The relation gets the usual
join table and rendered columns: run `mix brando.gen.blueprint_migration` as for
any block field ([Blueprint migrations](blueprint_migrations.md)). Several
rich-text fields can share one notes relation. Removing the `footnotes:` option
disconnects the field from its notes.

Footnotes work on top-level inputs only. A `footnotes:` option on an input in a
subform raises at compile time.

## Rendering footnotes

### Block fields

`Brando.Villain.parse/3` numbers references after it renders a whole block
field, so the numbers follow the rendered order across blocks, including
references a template moves. It then appends the endnote list. The render
stored at save includes both, so `render_blocks/1` needs nothing extra. Each
`parse/3` call numbers its own references, starting at 1.

Two options change this:

- `footnote_scope:` prefixes the IDs of references and notes (default
  `"article"`, which the stored render uses). When several block fields with
  footnotes share a page, parse them at request time, each with its own scope
  such as `"article-#{entry.id}"`, so their links do not collide.
- `footnotes: false` leaves the references unnumbered and adds no list.

### Rich-text fields

Preload the entry's block trees, including the notes relation, then render the
field and its notes with `render_rich_text/1`:

```elixir
entry = Repo.preload(entry, Brando.Content.BlockPreloads.for_schema(MyApp.Articles.Article))
```

```heex
<Brando.HTML.render_rich_text entry={@entry} field={:body} />
```

It takes `title` for the list's heading (default `"Notes & sources"`) and
`scope` for the IDs (default `"<singular>-<id>-<field>"`, such as
`article-12-body`). Without the preload it raises an `ArgumentError`.

For a custom layout, take the structured result:

```elixir
result = Brando.Villain.Footnotes.render_field(entry, :body)
# result.html: the text with linked, numbered references
# result.notes: in order, maps with :uid, :number, :id, :html and :reference_ids
```

`Brando.Villain.Footnotes.to_html(result, title: "Sources")` returns the text
followed by the endnote list. `Brando.Villain.Footnotes.outlet(result.notes, "Sources")`
renders the list alone, to place it elsewhere on the page.

### One sequence across several fields

To number several fields as one sequence, join their HTML before numbering it:
render each with `footnotes: false` (or take already rendered output, endnote
lists included), pass the combined HTML to `Brando.Villain.Footnotes.render/2`,
then `Brando.Villain.Footnotes.to_html/1`. `render/2` takes `scope:` and returns
the same `%{html:, notes:}` result as `render_field/3`.

### Output

A reference renders as:

```html
<sup data-footnote-uid="…" class="footnote-reference">
  <a href="#fn-article-…" id="fnref-article-1" role="doc-noteref" aria-label="Footnote 1">1</a>
</sup>
```

The list is a `section.footnotes` with `role="doc-endnotes"`, an `h2` heading
and an `ol`. Each `li` holds the note body and a return link to each of its
references. A note referenced twice keeps one number and gets two return links.

Note bodies render through their modules' ordinary templates, so images, video
embeds and download links render as they do elsewhere. Notes without a
reference are not rendered. A reference whose note is missing renders as
`span.footnote-unresolved`. The site's CSS styles all of this; Brando ships no
footnote styles for the site.

Footnote rendering parses HTML with Floki at runtime, so the application must
not restrict Floki to `only: :test`.

## Unused content

Brando never deletes a region's or a note's content on its own. Removing or
renaming a region ref leaves an **unmatched region**; removing the last
reference to a note in the text leaves an **unreferenced footnote**. The editor
lists them under **Unused content** on the owning block, or beside the owning
rich-text field, with these actions:

- **Open** shows the content to inspect or edit.
- **Remap** moves an unmatched region to an empty region on the same block.
  Only regions whose module set allows all its blocks are offered. The blocks
  keep their order and unsaved edits.
- **Restore reference** inserts a reference to the note back into its text. It
  is offered while that text ref or field still exists.
- **Delete** removes the content. The block bin can undo this until the entry
  is saved.

## Copying blocks

Duplicating a block copies its regions and notes and points the copied
references at the copied notes. Images, files and videos stay shared library
assets. Pasting only a reference into another block's text does not copy its
note; the reference shows as missing rather than pointing at unrelated content.

## Limits

- Region and note palettes offer ordinary modules only. Multi modules,
  containers, fragments, and modules with their own regions or with footnotes
  on are left out, so regions and notes do not nest.
- Use ordinary modules to own regions and footnoted text refs.
- Rich-text footnotes work on top-level form inputs only, not in subforms.
- Live preview re-renders the whole entry when a region or note changes, so
  the numbers and the endnote list stay in step.
