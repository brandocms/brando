# Use typography and color to establish hierarchy

The admin's typefaces are Schibsted Grotesk for text and JetBrains Mono for
code, keys and technical values, both variable and under the SIL Open Font
License ([`assets/fonts`](../../../../assets/fonts), [`fonts.css`](../../../../assets/css/fonts.css)).
Write `var(--brando-font-sans)` or `var(--brando-font-mono)`, never a family
name; they come from `theme.typography.families`. Weights run from 400: use
400 for text and 500 for emphasis and headings.

Every fixed font size is a step of the type
scale, `theme.text` in the admin's `europa.json5`, which
[`assets/css/tokens.css`](../../../../assets/css/tokens.css) sets as `--brando-text-*`.
Write `font-size: var(--brando-text-sm)` (or the size in a `font` shorthand),
never a pixel size: `.github/scripts/check_css_font_sizes.sh` rejects pixel font
sizes in CI. A size between two steps takes the nearer one. The editor's
content and inputs keep their responsive sizes from `theme.typography.sizes`
(`@fontsize input`, `@fontsize h2`), which grow with the screen.

| Token | Default | Use |
| --- | --- | --- |
| `--brando-text-2xs` | 10px | Counters, keyboard hints, overlines |
| `--brando-text-xs` | 11px | Help text, metadata, badges |
| `--brando-text-sm` | 12px | Default UI text: buttons, rows, labels |
| `--brando-text-md` | 13px | Body text, descriptions, inputs |
| `--brando-text-lg` | 14px | Item and card titles, settings inputs |
| `--brando-text-xl` | 16px | Section titles (h3) |
| `--brando-text-2xl` | 18px | Drawer, panel and dialog titles |
| `--brando-text-3xl` | 20px | Large titles, sidebar rows, empty states |
| `--brando-text-4xl` | 22px | Section headings (h2), modal titles |
| `--brando-text-5xl` | 26px | Page headings on a phone, large figures |
| `--brando-text-6xl` | 32px | Page headings (h1) |

Small metadata is subordinate, but it still needs to be readable at normal
zoom. Do not shrink essential instructions to make a layout fit.

Use regular or medium weights, restrained borders, and minimal shadows. Sentence
case suits headings and actions. Reserve small uppercase labels for short context
labels, and use monospace for keys, configuration, and technical values.

The approved palette is defined once, as custom properties in
[`assets/css/tokens.css`](../../../../assets/css/tokens.css) set from the admin's
EuropaCSS theme (see [Application colours](#application-colours) below). Use
the token, not its value. The values below are Brando's defaults:

| Role | Token | Value |
| --- | --- | --- |
| Main text | `--brando-ink` | `#272b2a` |
| Secondary text | `--brando-muted` | `#626b66` |
| Text and icons on a dark fill (accent buttons, checks, photos) | `--brando-ink-inverse` | `#ffffff` |
| Placeholders, disabled text, counters | `--brando-faint` | `#9aa39c` |
| Borders and dividers | `--brando-line` | `#dce2dc` |
| Border on hover or focus, drop target outline | `--brando-line-strong` | `#bacabd` |
| Dividers between rows inside a framed list or table | `--brando-line-soft` | `#ecf0ea` |
| Main accent (actions, links, focus, progress) | `--brando-accent` | `#254e3f` |
| Primary button on hover | `--brando-accent-hover` | `#1a3d30` |
| Page ground | `--brando-surface-page` | `#fafbf9` |
| Content, cards, inputs | `--brando-surface` | `#ffffff` |
| Subform surface | `--brando-surface-subform` | `#f8fbf6` |
| Subform border | `--brando-line-subform` | `#e2e9df` |
| Table header and footer rows, shaded fieldsets | `--brando-surface-shaded` | `#fbfcfa` |
| Row hover | `--brando-surface-hover` | `#f5f8f3` |
| Selected item, drop target | `--brando-surface-selected` | `#eef3ea` |
| Neutral notice, section header, icon tile, hovered secondary button | `--brando-surface-tint` | `#f1f5ef` |
| Modal and loader backdrop | `--brando-overlay` | `rgb(30 43 37 / 30%)` |
| Badge fill / ink | `--brando-badge-bg` / `--brando-badge-ink` | `#eef0eb` / `#566153` |
| Needs attention (missing alt text, unsaved, warning badges): tint / rule / ink | `--brando-attention` / `--brando-attention-line` / `--brando-attention-ink` | `#fbefda` / `#e4b866` / `#87662d` |
| Done or fine (passed check, added line, active or connected, finished import): tint / border / ink | `--brando-success` / `--brando-success-line` / `--brando-success-ink` | `#e8f2e9` / `#d0e3d2` / `#2f6343` |
| Errors (failed save or upload, invalid field, destructive action): tint / border / ink | `--brando-error` / `--brando-error-line` / `--brando-error-ink` | `#fff1ed` / `#e8ccc4` / `#8c4232` |
| AI: anything that calls a paid AI service, as text, icon, focus or fill / filled control on hover / hairline / hairline on hover / hover tint | `--brando-ai` / `--brando-ai-hover` / `--brando-ai-line` / `--brando-ai-line-strong` / `--brando-ai-tint` | `#634f8f`, the rest mixed from it |
| AI result waiting for review: tint / rule / ink | `--brando-suggestion` / `--brando-suggestion-line` / `--brando-suggestion-ink` | mixed from `--brando-ai` |
| Switch on / off | `--brando-switch-on` / `--brando-switch-off` | `#9cc79f` / `#c0c0c0` |
| Status: published | `--brando-status-published` | `#3cb371` |
| Status: pending | `--brando-status-pending` | `#f1ac00` |
| Status: draft | `--brando-status-draft` | `#636363` |
| Status: deactivated | `--brando-status-disabled` | `#cd5c5c` |
| Status: deleted | `--brando-status-deleted` | `#171a18` |

Modules can be given a colour. Blue, the default, draws a block's chrome with
the neutral roles above; pink, emerald and peach use
`--brando-module-<colour>-line`, `-tint`, `-ink` and `-dot` (the outline's
dot), which keep those categories apart in the block editor.

Utilities' authorization header uses `--brando-surface-tint`; its import and
export cards share `--brando-surface-shaded`. Screens don't keep tints of
their own: a blue or lavender panel becomes a neutral surface, and an "OK",
"added" or "active" state uses the success tokens.

## Application colours

`theme.colors` in [`assets/europa.json5`](../../../../assets/europa.json5) is the
admin palette, and a supported configuration API: an application changes the
admin's colours in its own `assets/backend/europa.json5`, which extends
Brando's. `tokens.css` sets these roles from it with `theme(colors.*)`:

| Palette entry | Role |
| --- | --- |
| `dark` | `--brando-ink` |
| `blue` | `--brando-accent` |
| `peachLighter` | `--brando-surface-page` |
| `peach` | `--brando-surface-subform` |
| `peachDarker` | `--brando-surface-selected` |
| `peachDarkest` | `--brando-line` |
| `overlay` | `--brando-overlay` |
| `status.draft`, `status.pending`, `status.published`, `status.disabled`, `status.deleted` | `--brando-status-*` |

```json5
// assets/backend/europa.json5
{
  extends: './node_modules/@brandocms/brandojs/europa.json5',
  theme: { colors: { dark: '#1d2422', blue: '#3a5f8a' } },
}
```

The application's entries merge into Brando's, so the rest of the palette
stays. `villain.main`, `villain.secondary` and `villain.popover` refer to
`blue`, `peach` and `dark`, and follow them. Application admin CSS can use
any entry with `theme(colors.*)` or `@color`. An application can also set a
role directly, `:root { --brando-accent: … }` in its `app` layer, which
outranks Brando's `tokens.css`; that changes the role at run time only, not
`theme(colors.*)` values compiled into other application CSS.

Every other role has an entry too, named after its custom property:
`muted` sets `--brando-muted`, `line.strong` `--brando-line-strong`,
`surface.hover` `--brando-surface-hover`, `attention.tint`/`.line`/`.ink` the
attention tokens (and `success.*`, `error.*` likewise), `badge.fill` and
`badge.ink`, `ai`, `module.<colour>.line|tint|ink|dot`, `nav.*`,
`presence.p0`–`p5`, `switch.on|off`, `tabbar` and `shadow` (the shadows'
ink). Roles mixed from another
(the AI hairlines, the suggestion tints) follow it.

The palette is also available at run time under its entry names:
`--brando-color-dark`, `--brando-color-blue`, `--brando-color-peach`,
`--brando-color-peach-lighter`, `--brando-color-peach-darker`,
`--brando-color-peach-darkest`, `--brando-color-overlay`,
`--brando-color-gray`, `--brando-color-gray-light`, `--brando-color-white`
and `--brando-color-black`, each set with `theme(colors.*)`. Use them in
application CSS that works with the palette; Brando's stylesheets use the
roles. A few earlier role names remain as aliases, such as
`--brando-color-background` for `--brando-surface-page`.

Do not add colour literals to admin stylesheets, `tokens.css` included: no hex
colours and no colour functions (`rgb()`, `hsl()`, `oklch()` and the like),
also inside data URIs. CI runs `.github/scripts/check_css_colors.sh`, which
fails on them in `assets/css`; it doesn't catch named colours, so use a role
there too. A colour that has no role yet gets an entry in `theme.colors` in
`assets/europa.json5` and a role in `tokens.css` set from it. For a
translucent version of a role, mix it with transparent:
`color-mix(in srgb, var(--brando-ink) 8%, transparent)`.

Native checkboxes, radios, range sliders and progress bars take the accent from
one `accent-color` on `:root` in `assets/css/base.css`; don't set it per
component. Picker and listing status dots use the status tokens.

Keep tinted surfaces subtle, and check text and control contrast in the
rendered interface. Status needs a textual label as well as color.
