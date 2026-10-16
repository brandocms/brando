# Entry editor heading and settings screens

Approved in #2982 (October 2026). An entry editor heads itself with the entry:
a 12px muted breadcrumb (the content type's icon, its listing name linked to
the listing, the blueprint's own name for its entries where it has one, and
the language: `Projects · Case · EN`), then the entry's title as a 32px ink
heading at weight 500, or "New case" before the first save. The status is one
pill below the title (dot, label, chevron) opening the choices as radios of
the entry form; choices the user may not save are disabled, following
`Engine.publication_allowed?/2`. `Form.EntryHeader` renders both, and
`EntryHeader.css` styles them. The heading follows the saved entry, so typing
in the title costs no server work.

The toolbar under it is split (approved October 2026) and keeps to one row.
On the left, straight on the page, the sections and drawers (Content, Meta,
History, Scheduled publishing) as `.pill-tabs--small`. On the right, in their
own white group with the bar's border, radius and surface: the editors
present as compact overlapping avatars with a subtle 1px border in each
editor's colour (the count of editors is in their tooltip), the save state ("Saved 23:20", "Unsaved changes", with the recovery
status in its tooltip), Recovery copies as a named icon (its tooltip includes
the pending count, and an amber dot marks pending copies), Notes as an icon
with a badge counting open notes,
Preview as an eye icon with a tooltip and optional menu, a "⋯" More menu (Languages, Share preview;
an item that doesn't apply is left out, and an empty menu isn't drawn) and
Save and close with its options. Long offline/recovery errors appear beneath
the toolbar, aligned right and wrapping within the page; their short label and
status dot stay beside Save, separated from the action icons by a hairline.
A connection loss alone gets neutral reconnecting copy; only unacknowledged
edits get the recovery-storage warning.
Status dots are `1cap` square to match their labels. Under 1366px Save drops its icon to keep the row; when the tabs and tools still don't fit, the tabs
scroll in their track, then the tools take a row of their own. On a phone the
tabs take a row of their own and scroll inside their track.

When the bar sticks, content scrolling under it would show between the two
groups, so the stuck bar sits on a band of the page colour, faded at its
foot. The Form hook watches a sentinel above the bar with an
IntersectionObserver and sets `is-stuck` through sticky JS; no `:has()`.

Following another editor (click their avatar) draws a 2px frame in their
presence colour round the editing area, fixed to its edges on screen, and a
chip under the toolbar, "Following Ingrid ×". The frame takes no clicks;
the chip's ×, Escape, the avatar again, or your own scroll or click stop
following. The followed avatar has a tinted background and a stronger coloured border. Nothing about following
sits in the toolbar.

Opening an entry (approved October 2026) shows the entry, never a modal.
The form reads the entry before its first render, so the heading, tabs and
fields arrive real. A light entry (up to 20 blocks) opens complete, and until
then the listing stays: the clicked row is tinted, says "Opening" after the
title and draws a 2px line along its foot (`openingRow.js`, from LiveView's
own `phx-click-loading` on the link, through sticky JS). A heavier entry
shows its fields read-only beside outlines of its blocks; the toolbar says
"Loading 115 blocks" where the save state goes, over a 2px line under the
bar, and its tools are disabled and quieter until the blocks have loaded.
Only when nothing of the entry is known yet (a reload, before LiveView
connects) is the whole form a skeleton, with real chrome and "Opening" in the
save-state slot. Skeleton bars shimmer and lines sweep by `transform` only,
and stand still under `prefers-reduced-motion`. `Form.EntrySkeleton` and
`Opening.css` draw all of it; the state is a class on the form root
(`is-loading-blocks`), not a `:has()`.

A singleton settings screen (Identity, SEO) passes `layout={:settings}` to
the form and puts `Workspace.header` above it: the eyebrow "Configuration",
the screen's name and one plain line on what it holds. Its tabs are pill tabs
under the heading, and its one Save sits in a sticky bar at the bottom with
the save state, leading on the left, clear of the editors' avatars. A
configuration entry with a listing (a menu, a global set) keeps the entry
heading and Save and close.
