---
name: brando-frontend
description: Build this Brando site's public frontend. Use when writing or changing CSS in `assets/frontend`, module markup and its `[b-tpl]` styles, palettes, Moonwalk reveal attributes, fonts, Jupiter modules or other site JS, or how a module looks in the admin's block editor.
---

# Brando site frontend

The public site is one Vite bundle in `assets/frontend`. EuropaCSS compiles
its CSS (load `brando-europacss` for the at-rules and `europa.json5`), and
Jupiter (`@brandocms/jupiter`) runs its JS. Modules are the unit of the page:
an editor stacks them, so each one is styled on its own.

## File map

| File | Holds |
| --- | --- |
| `css/critical.css` | First-paint hidden states only. Loaded by `js/critical.js` in dev, and inlined in production from the Vite manifest (`Brando.HTML.inject_critical_css`). |
| `css/app.css` | The imports, then site-wide rules and the Moonwalk walk styles. |
| `css/includes/bundles.css` | `@europa base` and `@europa arrows`; imported first, so the site's rules follow the reset. |
| `css/includes/common.css` | Element styles, `.label`, `.button`, `.textlink`, `--nav-height`. |
| `css/includes/modules.css` | The page rhythm, then one `[b-tpl="…"]` block per module. |
| `css/includes/navigation.css`, `footer.css`, `cookies.css`, `fonts.css` | What their names say. |
| `js/index.js` | The Jupiter `Application`. |
| `js/config/*.js` | One config per Jupiter module (`MOONWALK.js`, `HEADER.js`…). |
| `js/modules/` | The site's own JS modules. |
| `public/` | Copied to `priv/static` by `pnpm build`, served from `/`. |

A new module's styles go in `modules.css`; a new partial gets its own file in
`css/includes/`, imported from `app.css`.

## Modules

- A module's root element carries `b-tpl`; a module created in the admin
  starts as `<article b-tpl="{{ block.class }}"><div class="inner">`.
- Scope every rule for a module under its `[b-tpl="name"]`, so it can never
  leak into another module.
- `main > [b-tpl]` already gets `@space container`, and its `.inner` gets
  `@space padding-x indent $lg`. Style the content, not the frame.
- `main { @space gap blocks }` spaces the sections, so a module carries no
  outer vertical margin. For a tighter pair, pull the second one up on that
  adjacency: `[b-tpl="a"] + [b-tpl="b"] { @space negate(blocks, blocksInner); }`
  leaves a `blocksInner` gap.
- Text refs arrive wrapped: a paragraph-type text renders as
  `<div class="paragraph"><p>…</p></div>`, a lede as `<div class="lede">`.
  Put the ref in an element of your own and style its text as descendants
  (`.lead p`): the paragraphs carry their own margins, and the last one's is
  cleared by `.paragraph > :last-child`.
- Pictures render as `<figure>`; their `moonwalk` option puts
  `data-moonwalk` on that figure.

## Tokens over literals

Colours, type sizes and spacing come from `europa.json5`:
`@color fg bone.muted`, `@fontsize text/sm`, `@space margin-top md`,
`theme(colors.bone.hair)` in a `border`. A colour, size or step the design
needs and the theme lacks goes into `europa.json5` first, then into the CSS
by name. Literal pixels are for hairlines and small fixed geometry (a 1px
rule, a 7px dot).

## Palettes

A container block renders `<section b-section="namespace-key">` with the
palette's colours as `--<color key>` custom properties on it (`Brando.Cache.Palettes`
also writes them for `[b-section="namespace-key"]`). Style a palette-aware
module with `var(--<key>)`. `critical.css` hides every `[b-section]` until
Jupiter sets `data-app-ready="true"` on the body, once the fonts have loaded.

## Admin module previews

The block editor shows module markup with the admin's CSS, not the site's.
How a module looks there is styled in `assets/backend/css/app.css`, inside
`@layer app`, under the same `[b-tpl="name"]`. That file forces Moonwalk
elements visible under `.blocks-wrapper`; keep that rule.

## Moonwalk

**A `[data-moonwalk]` is revealed only inside a `[data-moonwalk-section]`.**
Moonwalk only observes walks inside sections, and `critical.css` hides every
walk under `html.moonwalk`, so a walk outside any section stays invisible.

Read [moonwalk.md](moonwalk.md) before adding or changing any Moonwalk
attribute, a named walk, a run, or `MOONWALK.js`.

## Jupiter modules

`js/index.js` creates the `Application` and starts modules in its callbacks:

- `Events.APPLICATION_PRELUDIUM` runs at `initialize()`, before fonts load and
  before the page is revealed. Moonwalk, the header and anything that sets a
  first-paint state start here.
- `Events.APPLICATION_READY` runs once the fonts have loaded, just before the
  fade-in. Lazyload, links and other behaviour start here.

Give a Jupiter module its options from a `js/config/NAME.js` that exports a
function of the app, as the existing ones do. The modules Jupiter exports are
listed in `node_modules/@brandocms/jupiter/src/index.js`.

## Fonts

Put the files under `public/fonts/<family>/`, add an `@font-face` in
`css/includes/fonts.css` with `url('/fonts/<family>/<file>.woff2')`, and add
the family to `theme.typography.families` in `europa.json5` (`main` is the
one `@europa base` sets on the body). To preload one, pass it to the root
layout's head: `<.head conn={@conn} fonts={[{:woff2, "/fonts/…"}]} />`.

## Verify

1. Run the site (`mix phx.server`, or `pnpm dev` in `assets/frontend`) and
   watch the terminal and Vite's overlay for EuropaCSS errors.
2. For CSS alone, from `assets/frontend`:
   `pnpm exec europa css/app.css --config europa.json5 --quiet > /dev/null`
   (exits non-zero on an error).
3. `pnpm build` writes to `priv/static` and fails on ESLint errors.
4. Look at the page at desktop and phone widths, scrolled through, so every
   Moonwalk walk has had a chance to reveal.
