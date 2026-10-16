- **The admin is set in Schibsted Grotesk and JetBrains Mono.** Both are
  variable fonts under the SIL Open Font License, shipped under their own
  names in the brandojs package (`assets/fonts`) and bundled by the
  application's Vite build with fingerprinted file names, so a new font
  never sits behind a year-old cached `/fonts/Main-Regular.woff2`. Stylesheets
  use them through `--brando-font-sans` and `--brando-font-mono`
  (`theme.typography.families`), and the installer no longer copies font
  files into `assets/backend/public/fonts`.

- **The listing's status menu is a menu like the others.** It uses the
  shared dropdown panel and `.menu-item` rows instead of its own 16px,
  unpadded rows in a black-bordered box.
