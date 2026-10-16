- **One scale of shadows and one backdrop.** Fifty shadows in five tints
  become `--brando-shadow-ring`, `-xs`, `-sm`, `-md`, `-lg`, `-xl`,
  `-inset` and `-overlay`, in one ink (`colors.shadow`), from
  `theme.shadows` in the admin's `europa.json5`. Modals, dialogs, drawers
  and the assistant share one backdrop, `--brando-scrim`
  (`colors.scrim`). Editors' presence glows mix from
  `--brando-presence-0`…`5`, so each editor's colour is defined once, and
  the switches' check and cross icons take their colour from the switch
  tokens. No admin stylesheet holds an `rgb()`, `rgba()`, `hsl()` or
  `hsla()` colour any more, and CI rejects new ones. A popover shadow that
  never rendered (it used a Sass expression) now does.
