- **The admin has one badge.** `.badge` is now a 20px label in the admin's
  text face, sentence case, with a 4px corner, and it replaces the badges
  that screens drew for themselves (users, cache, content transfer,
  authorization, SEO checks, module files, the assistant and others). Tones
  come from modifiers: `badge--success`, `badge--attention`, `badge--error`,
  `badge--ai`, `badge--outline`, and `badge--count` for a number beside a
  tab. Blueprint listing templates keep working: `lowercase`, `uppercase`,
  `mini`, `tiny`, `no-border` and `warning` still apply; `large` is gone
  (a listing that used it gets the normal badge) and `no-case` is no longer
  needed. A listing that relied on the old mono uppercase look writes
  `badge uppercase`.

- **A shared button, `.btn`, for admin screens.** Three sizes (`btn--sm`
  26px, default 30px, `btn--lg` 36px), the looks `btn--primary`,
  `btn--save`, `btn--quiet`, `btn--danger` and `btn--ai`, an icon-only
  `btn--icon`, and `btn-group` for joined buttons. Screens move over to it
  area by area. Its corners and heights are `theme.radius` and
  `theme.controls` in the admin's `europa.json5`, set as
  `--brando-radius-sm|md|lg` and `--brando-control-sm|md|lg|touch`, so an
  application changes them in its own `europa.json5`.

- **Unused button and badge styles are gone**: `.btn-primary`,
  `.btn-secondary`, `.btn-outline-primary`, `.btn-outline-secondary`,
  `.btn-small`, `.btn-stealth`, `.button-group-horizontal` and a few
  screen-specific rules that no template rendered. An application's own admin
  screens that used one of them get the browser's plain button; use `.btn`.

- **Every admin colour is in `europa.json5`.** The roles that only
  `tokens.css` held (`--brando-muted`, the line, surface and message tones,
  the AI violet, module, sidebar and presence colours, and others) now have
  entries in `theme.colors`, named after their custom property (`muted`,
  `line.strong`, `attention.ink`, `module.pink.dot`, …), so an application
  changes any of them in its own `europa.json5`. The compiled values are
  unchanged. No admin stylesheet holds a hex colour any more, `tokens.css`
  included, and CI rejects new ones.
