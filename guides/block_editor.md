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

`blocks` goes directly under `form do`, never inside a `tab`, `fieldset` or
`inputs_for`, where it fails to compile. The block editor renders as its own
form after the entry form: nested in the entry form it would be a form inside
a form, and every change to an entry field would resend all its blocks.

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
> sandboxed like Liquex. Only superusers create, change, import or delete
> modules and containers, in both authorization modes; no group can be
> granted it ([Authorization](authorization.md#scopes-and-defaults)).

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
  words, not a quoted path. Like `<.fragment>`, it renders into the entry's
  stored HTML when the entry is rendered: nothing for a fragment that is
  unpublished then, and a change to the fragment's status shows in the entry
  on its next save. Outside development a missing fragment renders nothing
  and logs a warning.
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

### Writing templates safely

HEEx escapes what it prints; Liquid does not. `{{ … }}` prints a value exactly
as it is stored. Rich text (text refs, rich-text fields, text and html vars)
is HTML, meant to be printed between tags as it is. Every other text value
(string vars, entry titles, globals, addresses) holds whatever an editor, an
import or an approved content assistant proposal put there, quotes and spaces
included. So:

- In an attribute, write double quotes around the output and pass text
  through `escape`, which encodes `"`, `'`, `&`, `<` and `>`. Unescaped, a `"`
  in the value ends the attribute and the rest becomes markup; a `'` or a
  space ends a single-quoted or unquoted one, and `escape` leaves spaces as
  they are.
- Between tags, `escape` a value meant as text as well: a `<` in a string var
  or a title otherwise writes markup.
- Never put rich text in an attribute; `strip_html` it, then `escape` it.
- Do not `url_decode` a value you print: it turns `%3C` and `%22` back into
  `<` and `"` after every check has passed. For a query string, `url_encode`
  the value.
- `escape` does not check an address's scheme. Make a link from a link var
  with `{% link %}`, which escapes its address and its text and drops a
  script address.

```liquid
{%- comment -%} Don't {%- endcomment -%}
<figure title='{{ caption }}' data-tracking={{ tracking_id }}>
<a href="/search?q={{ query | url_decode }}">{{ query | url_decode }}</a>

{%- comment -%} Do {%- endcomment -%}
<figure title="{{ caption | escape }}" data-tracking="{{ tracking_id | escape }}">
<a href="/search?q={{ query | url_encode }}">{{ query | escape }}</a>
```

<!-- usage-rules:end -->

## Named block regions

A **Blocks** ref (`:blocks` in [module definitions](module_definitions.md))
gives an ordinary module a named insertion point for its own collection of
module blocks, such as a sidebar. See
[Footnotes and block regions](footnotes.md#block-regions).

## Footnotes

Footnotes are notes attached to a text ref or a Blueprint rich-text field, each
a small collection of ordinary modules. They are off by default. See
[Footnotes and block regions](footnotes.md#footnotes) for configuration and
rendering.

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
