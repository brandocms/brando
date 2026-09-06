# Footnotes and named block regions

Footnotes belong to a specific text ref or Blueprint rich-text field. They are
off by default. Each note holds ordinary modules from a configured module set,
using the existing text editor, media pickers, uploads, ordering and save flow.

The editor's foot button inserts a reference and opens its drawer. Existing
references are numbered as editors mount and when blocks move. Numbers are
derived; Tiptap stores only a stable note UID. The drawer uses the same round
plus as the main block editor. Closing it retains the draft; saving the entry
saves its notes.

## Text refs

In a module's text ref configuration, switch **Footnotes** on and enter the
module set title, for example `Footnotes`. Put a text module first in that set:
it becomes the initial block in a new note. Add image, video and download
modules to offer supporting media through their existing controls.

Switching footnotes off hides the insertion button. Saved references and their
content remain readable and editable. The module definition controls this
capability; posted editor inputs cannot enable it.

## Blueprint fields

Declare a dedicated blocks relation and opt the input in explicitly:

```elixir
trait Brando.Trait.Blocks

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

Create the relation's usual entry-block join table and rendered columns using
the Blueprint migration workflow. The form mounts its storage automatically,
outside the main entry form; do not also declare `blocks :body_notes` in the
form. Use `enabled: false` inside the footnote options to stop adding notes while
keeping existing notes available. Removing the configuration entirely also
removes the field's connection to its notes.

Preload the entry's block trees with `Brando.Content.BlockPreloads.for_schema/1`.
Render the field and its notes in a site template with:

```heex
<Brando.HTML.render_rich_text entry={@entry} field={:body} />
```

For a custom layout, use the structured result:

```elixir
result = Brando.Villain.Footnotes.render_field(entry, :body)
# result.html: text with linked, numbered references
# result.notes: ordered maps with uid, number, id, html and reference_ids
```

`Brando.Villain.Footnotes.to_html(result, title: "Sources")` combines the text
and an accessible endnote list. `Footnotes.outlet(result.notes, "Sources")`
renders the list separately.

## Named block regions

Add a **Blocks** ref, give it a stable name such as `sidebar`, and configure its
module set. Its description is the editor-facing label, such as “Further
reading.” Place it in an ordinary module template using the normal ref syntax:

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

Content lives in an internal `:slot` block under its owner, matched by the ref's
name. Replacing a ref row does not replace its content. Renaming or removing a
region ref retains the subtree, but it is no longer rendered at that insertion
point. The owner shows these collections under **Unused content**.

## Recovering unused content

An unused collection still holds its content. Removing or renaming a region
definition, or removing the last inline reference to a note, never deletes its
body automatically. The editor lists unmatched regions and unreferenced notes
on their owning block, or beside the owning Blueprint rich-text field.

- **Open** lets you inspect and edit the retained content.
- **Remap** connects an unmatched region to an empty current region on the same
  block. Only destinations whose module set allows all its children are offered.
  The region and its children keep their identities and order, including pending
  edits. Populated destinations cannot be overwritten or merged.
- **Restore reference** inserts a marker for the existing note in its original
  text owner. It is available while that text ref or field still exists.
- **Delete** removes the collection explicitly. The block bin can undo this
  until the entry is saved.

Region remaps participate in collaboration and recovery copies. Their virtual,
signed `slot_remap` field authorizes only the selected region and owner; saves
recheck the current module definition and destination policy. Plain posted slot
metadata cannot rename persisted collections. No additional migration is needed.

## Rendering and numbering

`Brando.Villain.parse/3` resolves numbers after rendering the block field. This
gives one running sequence across its visible blocks, including references
reordered by templates. Repeated references share a note number and have
individual return links. Unreferenced note bodies do not appear in the output.

Each result includes `sup.footnote-reference` links and a `section.footnotes`
with an ordered list and backlinks. Note bodies use their ordinary module
templates, so images, video embeds and download links render normally. The site
owns their typography and layout; admin drawer CSS is not included on the site.

Use `footnote_scope: "article-#{entry.id}"` with `Villain.parse/3` when separate
block fields share a page. To number several results together, pass their
combined HTML to `Footnotes.render/2`, then `Footnotes.to_html/1`. Previously
rendered endnote sections can also be combined and renumbered this way.

Whole-block duplication copies note subtrees and remaps their references to new
UIDs. Images, files and videos remain shared library assets. Pasting only an
inline marker into a different owner does not copy its note body; missing
references are shown explicitly instead of pointing to unrelated content.

## Current scope and upgrading

Collection palettes contain ordinary local modules. Multi modules, containers,
fragments and modules with further regions or enabled footnotes are excluded
from those palettes. Blueprint footnotes currently require top-level inputs;
subforms need a separate owner implementation. Use ordinary modules as region
and text-ref owners. Live preview refreshes the complete render when a
collection changes so the note outlet and numbers stay together.

Upgrade migration `brando_169_add_block_slots` adds `slot_name`, `slot_kind` and
`slot_module_set` to `content_blocks`, including existing tenant schemas.
Footnotes use Floki at runtime: consumer applications which override Floki with
`only: :test` must remove that restriction. Existing entries need no content
conversion and gain no insertion buttons until explicitly configured.
