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
- **`assets/frontend/europa.example.json5`**, when the site still has it, is
  a fuller worked theme that nothing loads. Copy a token the design needs
  from it into `europa.json5` (more type sizes, the `sans` and `serif`
  families, more spacing steps), rather than writing one from scratch.
- Its tokens are px below `desktop_lg` and scale with the viewport from it,
  written `scale-from(n, desktop_lg)`. A new token follows the same pattern.
- `dpx` is relative to `dpxViewportSize`: `20dpx` is 20px at that viewport
  width. Set it to the width of the design's Figma frame.
- **Three ways to write a length:** `16px` stays fixed, `16dpx` scales at
  every breakpoint it covers, and `scale-from(16, desktop_lg)` is 16px below
  `desktop_lg` and 16dpx from it. `scale-from()` takes a unitless number and
  one breakpoint name, and works in tokens, in at-rules
  (`@space row-gap scale-from(149, desktop_lg) $lg`), inside `calc()`, and
  for font sizes (`'font-size': 'scale-from(16, desktop_lg)'`,
  `@fontsize scale-from(18, desktop_lg)`).
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
- A token map (spacing, typography sizes and line height, container, columns)
  takes breakpoint names, collection keys and `'*'`:
  `projectRows: { $sm: '96px', $lg: 'scale-from(149, desktop_lg)' }` is 96px
  on mobile, 149px from `$lg` and 149dpx from `desktop_lg`. A named breakpoint
  beats a collection, two collections that share a breakpoint are an error,
  and `'*'` fills the breakpoints left over. Write a token with the fewest
  keys that say it, `{ '*': 'scale-from(24, desktop_lg)' }` for one that only
  scales, rather than an entry per breakpoint.
- A size's breakpoint value may be a property object
  (`{ 'font-size': '32px', 'letter-spacing': '-0.02em' }`), and
  `__base__: { … }` emits shared properties outside the media queries.
- **Line heights:** write Figma's ratio, `'line-height': '22/16'` in a size or
  `@fontsize base/22/16`; both emit `1.375em`. A px line height on a scaling
  size stays px and warns `EU_LINE_HEIGHT` with the ratio to use. The ratio
  rounds to five decimals and can land a fraction short (`20/14` emits
  `1.42857em`); the site's own tokens write the `em` rounded up
  (`1.42858em`) so a line never comes up short.
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
| `6/12`, `0.5/11`, `0.5:0.5/11` | Columns plus the gutters between them: `0.5/11` is half a column, `1.5/11` one and a half columns and one gutter. `:n` adds n gutters: `0.5:0.5/11` is half a column plus half a gutter. |
| `scale-from(24, desktop_lg)` | 24px below the breakpoint, 24dpx from it. |
| `xs/2`, `xs*2`, `-md` | Divided, multiplied, negative. Anything more needs `calc()`. |
| `12px`, `2rem`, `40dpx` | Literals; `dpx` becomes `vw` against `dpxViewportSize`. |
| `between(20px-50px)` | Fluid within each breakpoint (matching px or rem). |
| `calc(100vw - var[container])` | `var[token]`, `var[1]` (one gutter) inside a calc. |

A trailing `cq` measures a size against the nearest inline-size container
instead of the element, for transforms, whose percentages read the element's
own width: `@space translate 0.5:0.5/11 cq` under a parent with
`container-type: inline-size`. A breakpoint query follows `cq`.

`dpx` works only inside Europa at-rules: a plain `padding: 40dpx` passes
through and the browser drops it. Write `@space padding 40dpx`.

## Breakpoint queries

A trailing query limits an at-rule: `iphone` (that range only), `>=desktop_md`,
`<ipad_landscape`, `<=mobile`, `>mobile`, `mobile/ipad_portrait`, `$sm`.
A bare name is that one range, not upwards. `/` lists breakpoints and is not
a range: `ipad_landscape/desktop_lg` leaves out `desktop_md`. For a span,
write `>=`, `<=` or a collection. Inside `@responsive`, an at-rule
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
@space negate(blocks, md);     /* margin-top: calc(-blocks + md) */
@space margin-left negate(1/4);      /* negates the gutter-adjusted width */
@space! padding-top 0 $lg;

@fontsize heading/5xl;         /* a size token; `/` or `.` for groups */
@fontsize text/lg/1.5;         /* with a line height */
@fontsize base/22/16;          /* Figma's 22px on 16px: 1.375em */
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
@grid;                         /* columns.count tracks of minmax(0, 1fr), gutter gaps, per breakpoint */
@grid subgrid;                 /* shares the parent grid's tracks */
@order -1 $sm;
@embed-responsive 16/9;        /* ratio box; iframe/video children fill it */
@abs100;                       /* absolute, top/left 0, 100% × 100% */
```

`@color` with an unknown token writes it as a literal (`@color fg blck` is
`color: blck`), so check the token name.

Config-driven blocks (paths start with `theme.` here, unlike `theme()`):

```css
@if theme.colors.grid { … }    /* a truthy value; a missing key is an error */

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
`--debug-tokens`, or `debugTokens: true` in the Vite plugin (the site's
`vite.config.js` sets it; builds leave the labels out), labels generated font
and spacing values with their token in the browser's dev tools:
`padding-top: 24px; /* --ec-space-token: "spacing.md"; */`. beta.2 leaves
`@space gap <token>` unlabelled at breakpoints where it scales.

An unknown at-rule (a typo such as `@spcae`, or a removed one) is only a
warning: it passes through, and the compile succeeds. Read the warnings, in
the terminal and Vite's overlay, as errors.

The Vite plugin, as `vite.config.js` sets it up:

```js
plugins: [europa({ config: './europa.json5', targets: ['defaults'], debugTokens: true })],
css: { devSourcemap: true, postcss: { plugins: [] } },  // keeps an old postcss.config out
build: { cssMinify: 'lightningcss' },
```

`targets` sets Vite's CSS targets as well; leave `build.cssTarget` and
`css.lightningcss.targets` unset. The executable is a platform-specific
optional dependency: install with optional dependencies on, inside the
Docker image for a release, and never copy `node_modules` between machines.

## Checking against Figma

Export the frame as a PNG, then, with the site running and a Chromium
started with `--remote-debugging-port=9222` and a throwaway
`--user-data-dir`:

```sh
pnpm exec europa compare http://localhost:4000/ --frame frame.png --width 1440 \
  --frame-json frame.json --output-dir comparison
```

It writes `overlay.png` (page and design at 50%) and `diff.png`. With
`--frame-json` (a Figma frame node, or a list of named boxes) it reports each
text and image box's offset from the design in CSS pixels; the spacing labels
from `debugTokens` name the tokens to look at for a gap that is off. Exit status 1 means
differences, 2 design elements it could not match. `europa studio`'s
**Design frame** panel overlays the PNG on the page interactively.

## Upgrading from 0.1.0-beta.0

`europa migrate` has no profile for native versions yet
(brandocms/europacss#133), so compare the compiled CSS instead. Before
bumping the packages, run
`pnpm exec europa css/app.css --config europa.json5 -o /tmp/before.css`, and
the same for every other entry (`css/critical.css` in the frontend); after
the bump, compile them again and diff. Two layout changes are expected:

- `@grid` takes `columns.count` per breakpoint with `minmax(0, 1fr)` tracks
  and `column-gap`. In the admin, whose preset has 6 and 16 columns, a
  `@grid` that was 12 columns no longer is.
- A fractional span (`@column 2.5/12`, `@space width 0.5/11`) counts only
  the gutters between its tracks, so it comes out wider; integer fractions
  are unchanged. Subtract the half gutter to keep the old width:
  `0.5:-0.5/11` is beta.0's `0.5/11`.

Then shorten the tokens and check that the output stays the same. A theme that used beta.1's `dpxScaleFrom` replaces it with
`scale-from()`; beta.2 fails the compile on the old setting and says so.
