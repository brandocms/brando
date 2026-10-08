---
name: brando-blocks-and-modules
description: Work with Brando's block editor content in this site. Use when adding block fields to a Blueprint, rendering blocks, writing or changing content modules and their Liquex or HEEx templates, refs, vars, containers, fragments or datasources, or exporting and importing module definitions.
---

# Brando blocks and modules

Editors compose entries from modules: templates with editable refs (block
primitives such as text, picture or gallery) and typed vars. Blocks are
rendered to HTML when the entry is saved, through the site's parser module.

## Read first

- `deps/brando/usage-rules.md`: the Block editor, Module definitions,
  Villain parser and Datasources sections.
- `deps/brando/guides/block_editor.md`, `module_definitions.md`,
  `villain_parser.md`, `datasources.md`, `pages.md`.

## Wiring blocks into a Blueprint

```elixir
trait :blocks

relations do
  relation :blocks, :has_many, module: :blocks
end

forms do
  form do
    blocks :blocks
  end
end
```

Without `trait :blocks` a `blocks` declaration fails to compile. Generate a
Blueprint migration afterwards. Render with
`<Brando.HTML.render_blocks entry={@entry} />`, which reads the HTML stored
when the entry was saved.

## Modules as files

Keep module templates in version control by exporting them, editing the files
and importing them back:

```sh
mix brando.modules export --out priv/modules --user 1
mix brando.modules import --from priv/modules --user 1 --dry-run
mix brando.modules import --from priv/modules --user 1
```

Tenant applications pass `--site` and `--environment` on every command.
Commit the definitions, templates and `modules.lock.json` together.

## Rules that bite

- Liquex templates reference refs as `{% ref refs.name %}` and vars bare, as
  `{{ key }}`. HEEx templates use `<.ref block={@block} ref={:name} />` and
  `@key`; var keys that collide with renderer assigns are rejected.
- HEEx module templates run as server-side Elixir. Only trusted administrators
  may edit them.
- Template edits apply to every entry that uses the module on its next render.
- Change block markup in the site's parser module, not in Brando.
