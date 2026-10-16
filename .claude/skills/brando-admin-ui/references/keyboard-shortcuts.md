# Keyboard shortcuts

Every shortcut is listed once, in `assets/src/shortcuts/registry.js`, with a
label in `BrandoAdmin.Components.ShortcutSheet.labels/0`; the sheet that `?`
opens is drawn from that list, and a unit test fails when a shortcut has no
label. A global shortcut is handled by the registry's own listener, and a hook
binds its handler with `bindShortcut(id, handler)` while it is mounted. A widget that
keeps its own keys (the form's ⌘S, TipTap, menus) still gets an entry, so the
sheet lists it, and matches the keys with `matches(id, event)` from the registry.

Plain keys are kept to `?`, sequences that start with `g`, and the listing's
`f` and `c`. NVDA and JAWS use single letters to move around a page in browse
mode, and a page cannot tell when that mode is on, so a new letter shortcut
would take keys from screen reader users. These keys never fire in a text
field, rich text or CodeMirror, or while a dialog has the focus, and the
sheet's "Single-key shortcuts" switch turns them off in the browser (WCAG
2.1.4). Shortcuts with ⌘ or Ctrl stay on. Show a shortcut with
`Primitives.shortcut` or the `shortcut-mac`/`shortcut-other` spans, so it
reads ⌘ on a Mac and Ctrl elsewhere.
