# Motion

Start feedback on the user's click and let it settle over 300–350ms. Small
movements make the editor feel friendlier: dialogs lift and fade, drawers slide
with their backdrop, menus settle into place, and blocks reveal or clip their
contents as their frame opens and closes. Inserted variables, subform rows and
identifiers use the same short reveal, without a colour flash. Keep controls
that straddle a row's edge visible during the reveal and at rest. Destination
pages fade in after LiveView navigation. Use the shared `--motion-enter`,
`--motion-leave` and easing tokens in `transitions.css`. Both the admin preference and the OS reduced-motion
setting must be respected; removing movement must also remove waiting for it.

Use `show_modal`, `hide_modal` and `toggle_drawer` for shared overlays. These
dispatch to `surfaceMotion.js`, which keeps visibility in LiveView's sticky
attributes and cancels an old animation when a new action reverses it. An exit
that precedes server removal must complete before LiveView removes the node.
Keep nested dialogs independently controlled, return focus to the opener, and
let server validation reveal the tab containing the error.

Form tabs and modal sections keep their fields mounted. Animate their opacity,
not their transform: a transformed ancestor temporarily changes the containing
block of fixed dialogs inside it. Test real motion as well as E2E's usual 1ms
mode, including delayed replies, quick reversals, and reduced motion. See
`e2e/playwright/tests/editor-motion.spec.js`. For manual E2E previews, start the
server with `BRANDO_E2E_REAL_MOTION=1`; normal timings then survive refreshes.
Automated tests keep their fast CSS by default.

The login reveals its box and form rows in one overlapping sequence, including
recovery and passkey actions. Login and logout get a fixed 350ms exit before
the native form submits: the login box fades around a spinner, or the sidebar
slides left as the app fades. The delay never depends on credentials or the
server response and is not a timing-attack defense. Intercept at document
bubbling, before LiveView tears down its sockets for native navigation; honor
canceled submissions and keep the original submitter and validation. Reduced
motion submits immediately. Guard the app's first paint with root-layout opacity
until its entrance animations are installed; hiding visibility would swallow
mount-time keyboard focus. A timeout reveals the page if initialization fails,
and late initialization must not hide it again. On a fresh app load the sidebar
and content arrive in sequence; skeleton fields appear progressively. Alerts and confirmations use
the same native-dialog close helper as Search and Keyboard shortcuts, including
OK, Escape and backdrop clicks. Notes stays mounted while sliding so drafts
survive closing and quick reversals. Field-note actions sit in a reserved gutter
at the far right of the label row (the whole row for inline variables). Offer
them on label hover or field focus, keep them reachable while crossing the row,
and never move a control or a focused note button to make room. Existing-note
indicators remain visible.

Live preview keeps device sizes in a tall segmented group, with icon actions
and tooltips above. Its full-height separator uses pointer capture, keeps
dragging at its width limits, and accepts the arrow keys, Home and End. Disable
iframe pointer input only during a drag; preserve the selected device when the
window changes size.
