- **The admin has a type scale.** Every fixed font size in the admin's
  stylesheets is one of eleven steps, `theme.text` in `europa.json5`
  (10, 11, 12, 13, 14, 16, 18, 20, 22, 26 and 32px), set as
  `--brando-text-2xs` … `--brando-text-6xl` in `tokens.css`, so an
  application retunes the admin's type in its own `europa.json5`. Sizes
  between two steps moved to the nearer one: 15px titles are 16px, 17px
  dialog titles 18px, the sidebar's 19px rows 20px, and the 30px page
  headings 32px like the rest. CI rejects pixel font sizes in the admin
  stylesheets (`.github/scripts/check_css_font_sizes.sh`). The responsive
  sizes of the editor's content and inputs (`@fontsize input` and the
  other `theme.typography.sizes` keys) are unchanged.
