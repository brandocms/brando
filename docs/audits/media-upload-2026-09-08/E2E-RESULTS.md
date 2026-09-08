# Full E2E validation — 8 September 2026

**197 enabled tests passed across the full run and targeted follow-ups. No unresolved failures.** The default configuration intentionally skipped 12 tests requiring explicit or tenant authorization-group modes.

The full `./test_e2e.sh --reset` run took 37.1 minutes: 179 passed, 16 failed, 12 intentionally skipped and 2 did not run because an earlier test in their serial group failed. The database reset, strict compilation, migrations, rollback/forward validation and seeding completed successfully.

The failures identified tests that still used the previous media UI: Add/Edit buttons, preview classes, picker labels and separate gallery upload inputs. Three workspace checks also matched the newly shared drawer classes. Eight spec files were updated to use the current controls. Their persistence checks remain, with explicit asset-ID checks replacing button-presence assertions where appropriate. No application-code changes were needed during this validation pass.

The three workspace reruns passed. The remaining 15 failed or blocked checks then passed in a fresh targeted run (2.5 minutes), including:

- Image, video and file media in notes, plus gallery and image-variable live preview.
- Media references and variables surviving later edits and save/reload, including the two previously blocked tests.
- Image/file/video field and variable recovery, replacement and reset without duplicate assets.
- Mixed-gallery order and deletions surviving recovery and save.
- SEO frontend metadata, robots and redirects; page creation and metadata; the full project workflow with all media types.

The initial targeted run was stopped after the three workspace passes to correct the note test's file-variable scope. Its three passes are retained in the verification record; the other 15 checks were run again. A test-filter escaping error before that run executed no tests.

The final result combines the original full run with these focused follow-ups; a second full-suite run was not performed. JavaScript syntax checks for all eight updated specs and `git diff --check` passed. The E2E consumer asset build had passed for the unchanged application assets before the full run.

[Per-test result record](full-e2e-results.json) · [Implementation review](IMPLEMENTATION.md) · [Screenshots](implementation.html)
