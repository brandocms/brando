# Content transfer design audit

16 September 2026 · issue #2827

Reviewed the implemented E2E application in Chromium at 1440 × 1050 and
390 × 844, using its actual Main font and compiled consumer assets.

## Findings and refinements

| Area | Final treatment and verification |
| --- | --- |
| Toolbar | Shared form toolbar radius and chip tokens; sage, blue and lavender workflows. Measured 34px desktop controls, 16px icons and 13px labels. Checked selected, hover and keyboard focus treatments. |
| Alignment | Sized the actual masked icon spans. Trimmed label boxes to the font's capital height and alphabetic baseline. Inspected close-ups alongside computed label and icon centers. |
| Content cards | Distinct title, content type and full configured language name; separate sentence-case status with an 11px dot. Reviewed draft, published, fragment, multiple-field and long-title entries. |
| Entry selection | Whole entries are the default, with block fields available under Advanced. Checked controls and a sage selected card. Explicit string values for `aria-pressed`; stable list and button identities. Tab, Space and Enter work, and focus survives selection updates. |
| Related content | Referenced entries appear in export review with an explicit Include entry action. Included relationships are remapped together; shared references remain visible for destination mapping. |
| Entry review | Pale blue headers group the source entry, create/update choice, publication policy and editable destination keys. Creates show meaningful values in two columns; updates show changed values before and after. Owned content expands into readable details. |
| Publication and recovery | New entries default to Draft with no schedule. Updates preserve destination publication unless changed explicitly. Conflicting keys block apply with inline feedback. Recovery explains whether it restores an existing entry or removes a newly created one. |
| Mobile navigation | Compact toolbar labels fit without hiding icons. A sticky selection shortcut reaches the export summary. The shortcut stays mounted so visibility changes preserve keyboard focus. |
| Review action | Removed inherited global primary-button sizing. Measured 36px height and a centered 16px icon. Blue ready state, neutral disabled state, aligned footer, and a stable upload-panel minimum height. |
| Upload states | Empty picker, uploading progress, uploaded bundle and invalid-file feedback. Uploaded files replace the contradictory native “No file chosen” message. Verified removal, replacement and a long filename at mobile width. |
| Contrast | Darkened the blue and lavender toolbar labels after measuring their tinted states. Ready review-action text measures 5.42:1; selected export text measures 4.82:1. |

## Validation

- E2E consumer asset build passed.
- All four focused content-transfer browser workflows passed: related-entry
  inclusion; whole-entry creation, conflict review, update and recovery;
  advanced block-field transfer and recovery; separate definition installation.
- 65 Elixir regression tests passed, covering transfer archives, definitions,
  block ownership, whole-entry validation, publication scheduling, related-entry
  remapping and recovery guards.
- The consumer Project integration test passed with its client, owned category
  join, gallery and self-referencing entry selection, including recovery.
- Export, upload and expanded import review fit the 390px viewport without
  horizontal document overflow.
- Elixir formatting and diff whitespace checks passed.

Browser measurements remain attached to the focused Playwright test results.
Screenshot inspection complements those measurements; this audit covers the
Chromium E2E application, not every consumer font or browser.

## Screenshots

- [Toolbar and content cards](content-transfer-export-detail.png)
- [Export, full desktop](content-transfer-export.png)
- [Export, mobile](content-transfer-export-mobile.png)
- [Selected field with keyboard focus](content-transfer-entry-focus.png)
- [Upload, ready](content-transfer-import-detail.png)
- [Upload, disabled](content-transfer-import.png)
- [Upload, invalid file](content-transfer-import-error.png)
- [Upload, mobile](content-transfer-import-mobile.png)
- [Expanded review, desktop](content-transfer-review-desktop.png)
- [Whole-entry review, detail](content-transfer-review-detail.png)
- [Expanded review, mobile](content-transfer-review-mobile.png)
- [Update comparison](content-transfer-update-desktop.png)
- [Related-entry inclusion](content-transfer-related-desktop.png)
- [Advanced block-field review, desktop](content-transfer-fields-review-desktop.png)
- [Advanced block-field review, mobile](content-transfer-fields-review-mobile.png)
