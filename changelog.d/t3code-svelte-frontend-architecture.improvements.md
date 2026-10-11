- **Smoother editor interactions.** Form tabs switch immediately in the browser
  and retain edits through server updates, while failed saves still reveal the
  field that needs attention. Dialogs, drawers, menus and section changes use
  gentle 300–350 ms motion; block collapse eases the surrounding layout. Dialog
  and drawer motion can reverse mid-animation, block configuration starts
  closing locally while the server catches up, and motion honours both the admin
  preference and the operating system's reduced-motion setting.
- **Calmer editor layout.** Recovery copies and Preview use named toolbar icons;
  long recovery/offline details wrap beneath the toolbar. Publication status
  sits below the title, and editor presence uses subtle coloured avatar borders. Empty page variables
  lose their redundant inner frame, added and removed rows slide smoothly without
  replaying hover fades after a deletion, and select
  choices update their submitted value immediately as the picker closes.
- **Softer sign-in and preview controls.** All login actions reveal together,
  submitting shows a spinner, and the app and skeletons arrive progressively.
  Login and logout finish a short exit before navigating, with a sidebar slide
  on logout; a first-paint guard prevents a flash before the app reveal,
  and the login screen no longer shows the CMS attribution.
  Live preview has grouped device controls, consistent hover states and a
  full-height resize handle that keeps dragging across the iframe and at its
  size limits, with keyboard resizing and a close button too.
- **Consistent calendar and search styling.** Calendar controls share a height,
  day numbers have more breathing room, and empty periods have a styled notice.
  Search, Keyboard shortcuts, alerts and confirmations share panel and backdrop fades in both directions.
  Search opens with skeleton rows and eases its first results into place,
  including after slow replies or reconnecting.
  Notes slides in and out while keeping an unfinished note. Field-note actions
  stay at the far right of their row and appear on label hover or field focus,
  without shifting inline variable controls. Floating panels use
  the login box's softer layered shadow.
- **Quieter navigation and listings.** Pages uses the same top inset as other
  listings, with compact controls and no zero-count badges. Large navigation
  sections contain their closing animation and the whole language panel slides
  up and down around a stationary trigger.
  Block configuration sits beside Build with AI instead of reserving an empty
  strip inside the editor. Offline storage warnings now distinguish connection
  loss from edits still waiting for acknowledgement.
  Dashboard empty cards align their text with the heading and use a light
  divider with more compact spacing.
- **Stable labels and closing menus.** Page-variable labels survive deleting
  another row and saving. Popovers keep their vertical layout throughout closing,
  and the processing progress bar stays hidden until needed, without flashing
  during page refresh.
- **Gentler Assistant feedback.** A violet thinking indicator accompanies the
  active run, new tool steps reveal word by word, and replies ease into view.
  Reply author labels and sparkles use the shared AI violet.
  Reopening history or reconnecting does not replay old steps, and both
  reduced-motion preferences are respected.
