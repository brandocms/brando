# Dashboard

Approved on 5 October 2026 (option E of the card studies). Recently updated
entries are cards in an auto-fill grid: the identifier's cover (or the content
type's icon on a grey field) at 16:10, the title, the content type with its
icon and language, then the status, when it changed and the last editor's
avatar. The title's link is stretched over the card, so the whole card opens
the entry. Drafts, scheduled publishing and "Expiring soon" (the next 14
days) sit in a 300px side column of white panels with a count; a scheduled or
expiring entry shows a small date tile. Panel headers have an edge-to-edge
divider; empty-state text aligns with the heading and uses compact spacing.
Under 1240px
the side column moves below the cards; on phones a card becomes a row with a
square cover. No content-type shortcuts: the sidebar already lists them.

The cover is the entry's actual image with a `srcset` of every size it has
(blur placeholders left out, each width as actually saved), so it is sharp on
retina screens; the identifier's stored thumbnail is too small for a card and
only stands in until an image has its sizes. The status dot follows
`.modal-status`: `1cap` square, the label and time trimmed to cap height.

`BrandoAdmin.Dashboard` loads the data (the editors in one query);
`components/dashboard.ex` renders it, styled in `SettingsWorkspace.css`.
