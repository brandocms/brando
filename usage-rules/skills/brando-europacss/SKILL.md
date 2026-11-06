---
name: brando-europacss
description: Write EuropaCSS for this Brando site with the native compiler. Use for CSS with `@space`, `@fontsize`, `@font`, `@color`, `@responsive` or another Europa at-rule, for `theme()`, for tokens and breakpoints in `europa.json5`, for the `europa` CLI or Vite plugin, and when porting CSS or a `europa.config.js` from an older site.
---

# EuropaCSS (native compiler)

EuropaCSS expands design tokens and at-rules (`@space`, `@fontsize`…) into
responsive CSS. Both of the site's Vite bundles compile it with the native
compiler: the `europa` executable from `@brandocms/europacss-cli`, run by
`@brandocms/vite-plugin-europacss` with the `europa.json5` beside
`vite.config.js`. There is no PostCSS step.

**Check the bundle's compiler first**, in its `package.json`:

- `@brandocms/europacss-cli` and `@brandocms/vite-plugin-europacss`: the
  native compiler, which this skill describes. The admin (`assets/backend`)
  is always on it.
- `@brandocms/europacss` with `europa.config.js` or `.cjs` and a
  `postcss.config`: the legacy PostCSS plugin, which a site installed before
  Brando 0.55 may keep for its frontend. Native-only syntax (`negate()`,
  `@mq`, `breakout`, `europa.json5`) does not compile there. Write CSS in the
  style the site's files already use, and port only when asked:
  [porting.md](porting.md) covers the config, the CSS and checking the result.

## The site's two configs

- **`assets/frontend/europa.json5`** is the public site's full theme, with no
  `extends`. Read its `breakpoints` and `breakpointCollections` before writing
  a query: they are not the admin's (`desktop_md` is 1280px here and 1200px
  in the admin preset).
- Its tokens are flat px up to `desktop_md` and the same number as `dpx` from
  `desktop_lg`, so the design scales with the viewport on large screens only.
  A new token follows the same pattern.
- `dpx` is relative to `dpxViewportSize`: `20dpx` is 20px at that viewport
  width. Set it to the width of the design's Figma frame.
- `setMaxForVw: true` freezes `vw` and `dpx` values at the largest breakpoint
  into lengths, from `container.maxWidth` there. That `maxWidth` must be a
  length (`1920px`); a percentage fails the compile.
- **`assets/backend/europa.json5`** (the admin) extends
  `./node_modules/@brandocms/brandojs/europa.json5`, Brando's admin preset,
  and lists only the application's changes to it.
- Admin CSS in `assets/backend/css/app.css` goes inside `@layer app`, which
  outranks Brando's own `brando` layer whatever the selectors.

## `europa.json5`

JSON5 data: comments, trailing commas, unquoted keys, single quotes; no
functions, imports or expressions. Duplicate keys and invalid references are
errors. Vite reloads the CSS when it, or a file it extends, changes.

| Key | Effect |
| --- | --- |
| `extends` | Path to a parent `.json5`/`.json`, relative to this file. |
| `theme` | The tokens (below). |
| `dpxViewportSize` | Reference width for `dpx` (default 1440). |
| `dpxViewportSizes` | Per breakpoint or `$collection`: `{ iphone: 375, $desktop: 1600 }`; beats `dpxViewportSize`. |
| `setMaxForVw` | Freeze `vw`/`dpx` at the largest breakpoint (above). |
| `nesting` | `'native'` (default) or `'expanded'`: nested rules written as explicit selector lists, each keeping its own specificity. |
| `responsiveOrder` | `'all-last'` (default) moves every media query after the common rules of its scope; `'generated-last'` leaves hand-written `@media` where written. |

**`extends` merging:** objects merge key by key, recursively; arrays,
scalars and `null` replace. A child's `families.main` array replaces the
parent's; its `colors.accent` leaves the other colours alone. One parent per
file, chains allowed, exact paths only (no package names).

**Theme sections:** `breakpoints`, `breakpointCollections`, `container`
(`maxWidth`, `padding`), `columns` (`count`, `gutters`), `spacing`,
`typography` (`base`, `families`, `sizes`, `lineHeight`), `colors`, plus any
custom key (read with `theme()`).

- Providing a section replaces the built-in defaults for it, token names
  included. Omit `typography.base` and 1rem is the default 18px.
- `theme.extend.<section>` merges one level only: `extend.spacing.md`
  replaces the whole `md` token, `extend.typography.sizes` the whole size map.
- Breakpoints are `'0'` or `'Npx'`, one of them `'0'`. A named breakpoint
  covers its own width up to the next one.
- Collections: `$sm: '<=ipad_portrait'`, `$tablet: 'ipad_portrait/ipad_landscape'`.
- A responsive value is a map per breakpoint: `{ iphone: '16px', desktop_lg: '16dpx' }`.
  `'*'` fills breakpoints without an entry. A size's breakpoint value may be a
  property object (`{ 'font-size': '32px', 'line-height': '120%' }`), and
  `__base__: { … }` emits shared properties outside the media queries.
- `'{colors.bone.full}'` refers to another token (the path starts inside
  `theme`). A whole-string reference keeps the type; an embedded one
  interpolates (`'1px solid {colors.line}'`). References resolve after merging,
  so they follow an override. Any `{…}` in a theme string is a reference.

## `theme()` in CSS

```css
.card {
  color: theme(colors.ink);
  border: 1px solid theme(colors.bone.hair);
  outline-color: theme(colors.focus, currentColor);  /* fallback when missing */
}
```

The path starts inside `theme` and reaches custom keys too. A missing path
without a fallback is an error. A breakpoint map is not a CSS value: use
`@space`, `@fontsize` or `@unpack` for those.

## Sizes

What `@space`, `@column` and the other sizing at-rules accept:

| Size | Means |
| --- | --- |
| `md`, `radius.regular` or `radius/regular` | A `spacing` token. An unknown key is an error. |
| `2`, `0.5` | Gutter multiples (`columns.gutters`), not pixels; `0` is 0. |
| `6/12`, `6:1/12` | A column fraction, gutter-adjusted; `:1` adds a gutter. |
| `xs/2`, `xs*2`, `-md` | Divided, multiplied, negative. Anything more needs `calc()`. |
| `12px`, `2rem`, `40dpx` | Literals; `dpx` becomes `vw` against `dpxViewportSize`. |
| `between(20px-50px)` | Fluid within each breakpoint (matching px or rem). |
| `calc(100vw - var[container])` | `var[token]`, `var[1]` (one gutter) inside a calc. |

`dpx` works only inside Europa at-rules: a plain `padding: 40dpx` passes
through and the browser drops it. Write `@space padding 40dpx`.

## Breakpoint queries

A trailing query limits an at-rule: `iphone` (that range only), `>=desktop_md`,
`<ipad_landscape`, `<=mobile`, `>mobile`, `mobile/ipad_portrait`, `$sm`.
A bare name is that one range, not upwards. Inside `@responsive`, an at-rule
inherits the scope; giving it a query of its own is an error.

## At-rules

`@space!`, `@color!` and `@abs100!` add `!important`; no other at-rule takes
`!`.

```css
@responsive $sm { … }          /* also >=desktop_md, mobile/ipad_portrait */
@mq 359px->740px { … }         /* px ranges, inclusive; 500px-> and ->800px */

@space container;              /* padding-x, max-width, margin auto, width 100% */
@space breakout;               /* full viewport width from inside a container */
@space margin-y xl;            /* any property, plus margin-x|y, padding-x|y */
@space padding-x container;    /* the container's padding only */
@space translateY md;          /* also translateX|Z, scale */
@space negate(blocks, blocksInner);  /* margin-top: calc(-blocks + blocksInner) */
@space margin-left negate(1/4);      /* negates the gutter-adjusted width */
@space! padding-top 0 $lg;

@fontsize heading/5xl;         /* a size token; `/` or `.` for groups */
@fontsize text/lg/1.5;         /* with a line height */
@fontsize xl(0.8);             /* multiplied */
@fontsize between(18px-22px);
@fontsize text/sm $sm;

@font main;                    /* a typography.families entry */
@font mono text/xs;            /* family + size; a query limits only the size */

@color fg bone.muted;          /* fg, bg, fill, stroke, border, border-top… */
@color bg transparent $sm;

@display flex/row/wrap $sm;    /* display, flex-direction, flex-wrap */
@column 4/12 $lg;              /* flex-basis and max-width */
@column-offset 1:1/12;         /* margin-left, sized as @column */
@grid;                         /* 12-column grid with gutter gaps; no arguments */
@order -1 $sm;
@embed-responsive 16/9;        /* ratio box; iframe/video children fill it */
@abs100;                       /* absolute, top/left 0, 100% × 100% */
```

`@color` with an unknown token writes it as a literal (`@color fg blck` is
`color: blck`), so check the token name.

Config-driven blocks (paths start with `theme.` here, unlike `theme()`):

```css
@if theme.colors.dbg { … }     /* a truthy value; a missing key is an error */

.stack {
  @iterate theme.spacing {
    &.gap-$key { @space gap $key; }
  }
}

.nav { @unpack theme.typography.sections.navigation; }  /* breakpoint map → media rules */
```

Bundles and functions:

```css
@europa base;      /* normalize, base element styles, root custom properties */
@europa arrows;    /* arrow helpers */
transition: transform 0.5s ease('quart.inOut');  /* sine quad cubic quart quint expo circ back */
```

`@europa base` expands where it is written and its reset beats rules above
it, imported ones included. Keep the bundles in their own file, imported
first, as the site's `css/includes/bundles.css` is. It sets `html` font-size
from `typography.base` and the body font from the `main` family, and needs
`main` and `mono` families, container values, and `columns.count` and
`gutters`.

## Nesting, order and output

- Native CSS nesting, with `&` as the parent. `@media`, `@responsive` and
  `@supports` nest inside a rule and wrap it.
- `&` joins only whole selectors: `&__title`, `&-pin` and `&foo` are errors;
  write `.card__title`.
- `@keyframes` stays at the root, never inside a rule.
- Sizing at-rules, `@iterate` and `@unpack` go inside a style rule; `@europa`
  and `@if` may sit at the root.
- Common rules come before media queries in each scope (`responsiveOrder`).
  Media never move across `@layer` blocks, `@import`s or unknown at-rules.
- Placeholders: define `%name { … }` at the root or in an unconditional
  `@layer`, and use it with `@extend %name;`. Only placeholders extend.
- `@import` takes exact local paths with the extension, or package paths
  through `node_modules`; no globs. Imports go first.
- Output is transformed for the browser targets (`targets` in the Vite
  plugin): vendor prefixes added, nesting lowered where needed, values
  normalised (`300ms` → `.3s`).

## CLI and Vite

From the bundle's directory (`assets/frontend` or `assets/backend`):

```sh
pnpm exec europa css/app.css --config europa.json5 --quiet > /dev/null  # validate; non-zero on error
pnpm exec europa css/app.css --config europa.json5 -o /tmp/app.css      # look at the output
pnpm exec europa studio --config europa.json5                           # local token and preview UI
```

Without `--config`, the CLI uses the built-in defaults, not the site's theme.
`--debug-tokens` (or `debugTokens: true` in the Vite plugin) labels generated
font sizes in the browser's dev tools.

An unknown at-rule (a typo such as `@spcae`, or a removed one) is only a
warning: it passes through, and the compile succeeds. Read the warnings, in
the terminal and Vite's overlay, as errors.

The Vite plugin, as `vite.config.js` sets it up:

```js
plugins: [europa({ config: './europa.json5', targets: ['defaults'] })],
css: { devSourcemap: true, postcss: { plugins: [] } },  // keeps an old postcss.config out
build: { cssMinify: 'lightningcss' },
```

`targets` sets Vite's CSS targets as well; leave `build.cssTarget` and
`css.lightningcss.targets` unset. The executable is a platform-specific
optional dependency: install with optional dependencies on, inside the
Docker image for a release, and never copy `node_modules` between machines.
