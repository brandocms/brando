# Buttons and badges

The admin has one button and one badge; a screen picks
a size and a look from them instead of drawing its own. Their sizes are
`theme.radius` and `theme.controls` in the admin's `europa.json5`, which
[`assets/css/tokens.css`](../../../../assets/css/tokens.css) sets as custom properties;
an application changes them in its own `europa.json5`, as it does the palette:

| Token | Value | Used for |
| --- | --- | --- |
| `--brando-radius-sm` | 4px | Badges and small chips |
| `--brando-radius-md` | 6px | Buttons |
| `--brando-radius-lg` | 8px | Inputs and cards (`--brando-input-radius`) |
| `--brando-control-sm` | 26px | Toolbar and inline buttons |
| `--brando-control-md` | 30px | The default button |
| `--brando-control-lg` | 36px | A form's Save |
| `--brando-control-touch` | 40px | Every button's minimum on a coarse pointer |

**Shadows** come from `theme.shadows`, in one ink (`colors.shadow`); use the
step, not a shadow of the screen's own:

| Token | Used for |
| --- | --- |
| `--brando-shadow-ring` | A 1px hairline around a raised surface |
| `--brando-shadow-xs` | Inputs, tabs, a selected segment |
| `--brando-shadow-sm` | Cards and thumbnails |
| `--brando-shadow-md` | Dropdowns, popovers and floating buttons |
| `--brando-shadow-lg` | Menus, toasts, notes and the entry header's panels |
| `--brando-shadow-xl` | Modals and large floating panels |
| `--brando-shadow-inset` | A field's inner shade |
| `--brando-shadow-overlay` | The login box's deep lift |

Behind a modal, dialog or drawer, use `--brando-overlay` (`colors.overlay`).

**Buttons** ([`Btn.css`](../../../../assets/css/components/Btn.css)):

| Class | Use |
| --- | --- |
| `.btn` | The default: a bordered 30px button |
| `.btn--sm`, `.btn--lg` | 26px in toolbars and rows; 36px for a form's Save |
| `.btn--primary` | The screen's main action, in the accent fill. One per area |
| `.btn--save` | A form's Save: the accent on a tint, at `--lg` |
| `.btn--quiet` | No frame until hovered: tools, Cancel, secondary row actions |
| `.btn--danger` | Destructive actions; with `.btn--primary`, filled, for the final step of one |
| `.btn--ai` | An action that calls a paid AI service |
| `.btn--icon` | Icon only, square; it still needs a name (see [Icon-only buttons and tooltips](icon-buttons-and-tooltips.md)) |
| `.btn--pill` | Fully rounded. Only for toggles |
| `.btn-group` | Buttons joined into one control, rounded at the ends |

Actions are rectangles; the pill shape is kept for things that switch state or
filter (toggles, filter chips, [tabs](tabs.md)). Rows in dropdowns and
menus are menu items, not buttons.

**Badges** (`.badge` in [`global.css`](../../../../assets/css/global.css)) label a state,
a type or a count: 20px, 11px text, sentence case, a 4px corner.

| Class | Use |
| --- | --- |
| `.badge` | Neutral: a type, a role, a count of things |
| `.badge--success`, `.badge--attention`, `.badge--error` | The message tones: done or active, needs attention, failed |
| `.badge--ai` | An AI result or state |
| `.badge--outline` | A hairline and no fill: a file type, a protected flag |
| `.badge--count` | A number beside a tab or heading; a tone modifier tints it (`badge--count badge--attention`) |
| `.badge-dot` | A status dot inside a badge, one cap high |

Don't add a badge class for a screen: give `.badge` a tone, and place it with
a contextual rule (`.my-heading .badge { margin-left: auto; }`).

## Menu items

A row in a dropdown, popover, context menu or picker list is a `.menu-item`
([`Menu.css`](../../../../assets/css/components/Menu.css)), not a button: 32px (40px on
a coarse pointer), 12px sentence-case text, a muted 14px icon before the label,
a 4px corner and the hover tint. The menu owns its panel (border, shadow,
placement, `%admin_dropdown_panel`); the row's look is always this one.

| Class | Use |
| --- | --- |
| `.menu-item` | A row: icon, label, then a hint |
| `.menu-item--danger` | Deletes or discards: red text, red tint on hover |
| `.menu-item--ai` | Calls a paid AI service: violet |
| `aria-selected`, `aria-checked`, `aria-current`, `.is-selected` | The current choice: the accent on the selected tint |
| `.menu-item-hint` | A shortcut or count after the label, at the row's right edge |
| `<span>label<small>…</small></span>` | A second line under the label: wrap both in a span, since the row is a flex row |
| `.menu-separator` | A rule between groups of rows; rows have no rule between each other |
