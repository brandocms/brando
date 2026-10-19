# Tab views

Every tab view in the admin is **pill tabs**, like the module editor's "In the
block / Configure modal" switch, shared as `.pill-tabs` in `TabSwitch.css`.
The track is `--brando-surface-shaded` with a 1px `--brando-line-soft`
border, a 22px radius and 3px of padding. Tabs are 13px/18px
(`--brando-text-md`) with 6px 14px of padding, muted by opacity. The selected
tab is a raised `--brando-surface` pill (`--brando-shadow-xs`, weight 500). Do not use underlined tabs, tinted tabs or
button groups.

```heex
<nav class="pill-tabs" aria-label={gettext("Sections")}>
  <button type="button" aria-current={@tab == "export" && "page"}>
    <.icon name="upload" />{gettext("Export")}
  </button>
  <button type="button" aria-current={@tab == "history" && "page"}>
    {gettext("Recent imports")} <span class="pill-tabs-count">{@count}</span>
  </button>
</nav>
```

- Mark the selected tab with `.active`, `aria-current="page"`,
  `aria-selected="true"` or `aria-pressed="true"` (pass a string:
  `to_string(@tab == key)`; a bare boolean renders no value).
- An icon goes before the label; a number goes after it in
  `.pill-tabs-count`. A badge with its own meaning, like the SEO score, keeps
  its own class.
- `.pill-tabs--small` is the compact size for toolbars inside a panel (the
  history drawer, the assistant's preview controls).
- A track with one tab shows it as a plain caption.
- The link pickers' `Input.radios` take the same look through
  `.link-picker-modes .radios-wrapper`.
- A sticky bar that holds tabs and actions (the module editor) is a white bar
  around the track. The entry form's toolbar is split instead: see
  [Entry editor heading and settings screens](entry-heading-and-settings.md).
  A tab bar's own class (`.transfer-tabs`, `.activity-tabs`…) is for its
  layout and tests only.

Two things are not tab views and keep their own look: the small mono language
pills on translatable fields (`.i18n-tabs`), and toggles and filters (Grid /
List switches, status filters, filter chips). Section rails in modals
(`Content.modal_sections`) are vertical navigation, not a tab bar.
