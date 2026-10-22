# Icons

The admin uses [Lucide](https://lucide.dev/icons) at stroke width 1.5,
rendered with `<.icon name="…" />` (`Brando.HTML.Icon`) or `Icon.svelte` as
`<span data-icon class="lucide-name">`, masked by one cached stylesheet that
`Brando.Icons` generates. Use current Lucide names only;
`test/brando/icons_test.exs` fails on a literal name Lucide doesn't have. Size
icons with `width`/`height` and colour them with `color`. Target one icon with
`.lucide-name`. To change the vendored set, run
`mix brando.lucide.update VERSION`.

Keep icons as masked spans. An SVG sprite (`<svg><use href>`) was measured on
the 115-block e2e entry: one extra node and four dynamics per icon cost 13% on
mount and broke the bench's payload budget.

## Blueprint content-type icons

A blueprint declares its icon in its body:

```elixir
content_icon "folder-kanban"
```

`Brando.Blueprint.get_icon/1` resolves it, falling back to `file`. The sidebar,
the link picker's “Content types”, entry identifiers and
listing headers all use it, so a content type looks the same everywhere.

## Sidebar rows

Every sidebar row has an icon; items without one show `dot`, so the column
stays aligned. Top-level and sub-item icons share one 20px column (sub-item
glyphs are 16px, centred in it), so every label starts on the same line.
Labels are trimmed with `text-box: trim-both cap alphabetic`, so the text
centres on the icon's centre line: aim for under 0.5px between icon centre and
cap centre. Rows are 32px (top level) and 30px (sub-items) with no block
padding. Browsers without `text-box` sit the label a pixel or two high, which
is acceptable.

Calendar (`/admin/calendar`) is a fixed row after Dashboard, in
`BrandoAdmin.Menu`; Search follows Dashboard directly.

Search is a row too, built in by `BrandoAdmin.Nav` rather than configured: a
button after Dashboard (or at the top of the first section) that opens the
command palette, with the shortcut faint at its end (mono 11px, the muted nav
colour at 60%). It is never the current row. On phones, where the sidebar is
hidden, the round `.mobile-search` button opens the palette instead.

The palette opens with skeleton rows in a reserved results area. Its first
server reply crossfades into place while the body eases to the content height;
the search field stays usable throughout. Keep stale results inert while
loading, honor reduced motion, and retry initialization after reconnecting.
Typing subsequent queries does not restart the opening skeleton.

Configuration's submenu is grouped: Site, Publishing, Building blocks
and Operations, each under a small heading in the section labels' mono capitals
(10px, muted, no rule), aligned with the icon column, 10px between groups. A
group with nothing the user may open has no heading. In `BrandoAdmin.Menu`
each item names its `group` and the submenu lists the headings as `groups`;
`items` stays one flat list in group order for the palette and page titles,
and the palette also finds a screen by its group's name. Each group is a
`role="group"` labelled by its `h4`, which is never a link; the
`Brando.Navigation` hook fades and hides the headings with the links. Put a
new Configuration screen in the group where an editor would look for it.
