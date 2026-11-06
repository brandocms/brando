# Porting from the PostCSS plugin

Older Brando sites compile CSS with the PostCSS plugin `@brandocms/europacss`
(0.x or 1.0 betas), configured by `europa.config.js` or `.cjs` and run from
`postcss.config.js`. The native compiler refuses JavaScript configs and
rejects several things the plugin allowed. Port the config first, then the
CSS, then compare the result.

## The config

```sh
pnpm exec europa migrate-config europa.config.cjs -o europa.json5
```

It converts a static object, and callbacks that simply return one
(`colors: () => ({…})`); anything computed must be written out by hand. It
never overwrites an existing file. Then:

- Breakpoints become `'0'` or `'Npx'` strings, one of them `'0'`.
- `typography.paddingDivider` is deprecated; drop it.
- `presetEnv` becomes the Vite plugin's `targets`.
- Set `typography.base` if the old site relied on another root size: the
  native default is 18px, and it now sets `html`'s font-size, not `body`'s.
- `migration.mediaPacking: 'none'` tells the migration tool that the old build
  did not pack or sort media queries (it changes no compiled CSS).
- To keep the old output while porting, `nesting: 'expanded'` and
  `responsiveOrder: 'generated-last'` are closest to the plugin's.

Swap the dependencies: remove `@brandocms/europacss`, the PostCSS config and
its plugins; add `@brandocms/europacss-cli` and
`@brandocms/vite-plugin-europacss`, and set up `vite.config.js` as in
SKILL.md.

## The CSS

```sh
pnpm exec europa migrate css/app.css --from 1.0.0-beta.6 --config europa.json5 --check
```

`--from` takes `1.0.0-beta.6`, `1.0.0-beta.11` or `1.0.0-beta.16`; for a
0.x source use `1.0.0-beta.6`, which does not cover every 0.x change.
`--summary`, `--details` and `--json` report; `--fix` rewrites simple suffix
selectors only.

What changed:

| Legacy | Native |
| --- | --- |
| `@row N/wrap/GAP` | Error. Write the flex row out: `display: flex; flex-wrap: nowrap` and `@space margin-left 1` on every child but the first of each N (`&:nth-child(Nn+1) { margin-left: 0 }`). `gap` is not equivalent where children carry margins. |
| `@container;` | Parse error. Use `@space container;`. |
| `&__title`, `&-pin`, `&foo` | Errors. Write the full selector. |
| `@nest` | Error (`EU_LEGACY_NEST`); native nesting needs no keyword. |
| `@at-root` | Error. |
| `@keyframes` inside a rule | Error; move it to the root. |
| `@column 6/12@md` | Error; write `@column 6/12 md`. |
| `@column-typography` | Removed; only warns as an unknown at-rule, so it silently does nothing. |
| IE hacks (`*zoom: 1`) | Errors. |
| `@fontsize!` and other `!` forms | Only `@space!`, `@color!`, `@abs100!` remain. |
| An unknown spacing or size key | Was `NaNvw`; now an error. |
| Named breakpoint ends at `next - 1px` | Ends at `< next`. |
| `vertical-rhythm()` | Scales the whole value. |
| `@color` breakpoint argument (ignored in beta.6) | Now applies. |
| `@space container <query>` across breakpoints (beta.6: first one's values) | Each breakpoint's own values. |

`between()` keeps the legacy interpolation anchors. `@mq`, arrow ranges and
the `breakout` and `negate` shorthands are new.

## Check the result

Compile with `--quiet` until there are no errors and no warnings, then compare
the rendered pages before and after:

```sh
pnpm exec europa compare <url> --before old.css --after new.css --stylesheet <href>
```

It needs Node 22+ and Chromium. Calc precision changed, so expect sub-pixel
differences; compare with a small threshold.
