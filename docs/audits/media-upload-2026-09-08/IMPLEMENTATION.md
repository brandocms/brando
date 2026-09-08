# Media experience — implementation review

8 September 2026 · `codex/unified-media-experience` · local worktree, not deployed

[Open the visual review](implementation.html) · [Original audit](AUDIT.md) · [Original 37 screenshots](screenshots.html)

## Full E2E validation

**197 enabled tests passed across the full run and focused follow-ups; no unresolved failures.** The default configuration intentionally skipped 12 authorization-mode-specific checks. The first full run found 16 tests using the previous media controls or a broad workspace selector; those tests and the two checks blocked by their serial group passed after their interactions were updated. No application-code changes were needed during this validation pass. See the [full result record](E2E-RESULTS.md) for counts, scope and per-test evidence.

## Control refinement

The Gallery toolbar now joins Upload media, Browse images and Browse videos in one group. All three use 12px text, identical padding and 32px desktop height; upload retains its green treatment. A modal primary-button override had made upload larger, so the toolbar now explicitly applies the same proportions to every segment. Remove icons align with the font's capital-height text box.

Configure image joins Edit/Crop and the Replace menu, with Remove in red. The same image action grouping applies to the block preview. Replacement still offers Upload replacement and Browse library. Fresh 1440px and 390px application captures are recorded under `implementation/revision-3`; the narrow-screen menu remains within the dialog.

After this refinement, the E2E consumer build and whitespace checks passed. Two focused E2E checks passed: opening Edit/Crop from the image configuration panel, and file-ref replacement plus mixed-gallery upload/save/reopen. The verification recorded below describes the preceding implementation rounds.

## Revision against approved work on `next`

The second design review uses the approved workspace implementation directly: `2439b502b` (modal and form sweep), `e8e3777fa` (shared listing workspaces), and the current Assets Images/Videos layouts, alongside [the Admin UI design guide](../../admin-ui-design.md). The shared `FileBrowser` and `.media-workspace` rules supply the folder rail, breadcrumb, spacing, and compact controls. Contextual pickers retain their existing selection and query owners.

- **Image details:** a clearly bounded 540px workspace drawer with a padded icon/title header, contained preview and focal point, compact Edit/Crop and Replace actions, a separate library-metadata section, and a fixed Done footer. Shared metadata remains distinct from ref overrides.
- **Browsers:** Images, Files and Videos share the Assets folder workspace, quiet selected rows, readable metadata, and the same responsive header. Video URL/upload actions sit beside the collection heading. Upload-folder confirmation uses that same panel with its actual destinations and actions in a fixed footer.
- **Gallery variable:** one toolbar, numbered media rows with thumbnails and filenames, quiet item removal, and a separated footer. Video thumbnails have a visible fallback while a preview is unavailable. The existing gallery persistence boundary is retained.
- **Video playback:** Play button and Progress bar continue the same lined settings rows as the inherited playback flags.
- **Keyboard behavior:** media drawers reuse the approved modal hook. Escape closes the active panel, menus return focus to their disclosure, and selecting an asset returns focus to its field.

The screenshot iterations exposed legacy drawer flex sizing and picker typography overriding the new shell, an overlay remaining active after a nested panel closed, a video thumbnail overflowing its column, excess mobile folder-rail height, and streamed grid tiles stacking into one column. These were corrected in the actual application, with intermediate captures retained under `implementation/revision-2`.

## The interaction contract

| Surface | At rest | Add or replace | Configure |
| --- | --- | --- | --- |
| Image, file and video form fields and variables | Compact thumbnail, filename and metadata | **Upload / Browse library** when empty; **Configure / Browse library** when populated. Drop anywhere on the field. | Existing owning drawer or variable dialog. Further actions remain there. |
| Picture, file and video block refs | Larger preview for the content being edited | Upload and Browse library when empty; Configure, Replace and Remove when populated. Both states accept drops. | Approved section-rail modal; each ref keeps its own overrides. |
| Gallery fields, refs, variables and resource editor | A collection with compact actions | Drop adds items. Image and video uploads resolve their own configurations. | Existing collection/object settings remain available. |
| Images and Files libraries | Existing library workspace | Upload uses the sticky manager. Image root intake names its actual destination and navigates there on completion. | Existing resource details; file-library replacement still preserves the shared file identity and URL. |

**Browsing stays visible.** The final form-field pass follows the original thumbnail-and-details layout supplied during review. Two adjacent buttons make a single split control; Browse library opens the existing browser directly. No extra dropdown click is required. Routine upload instructions, destination paths and replacement actions no longer fill the resting field.

**Dropping communicates the destination.** Dragging highlights the whole field and shows the configured folder. An image target with an unconfirmed default configuration opens the existing folder browser: choose a folder, then Upload here or Cancel. Once confirmed for that target and form session, later drops use the same folder. A mixed gallery confirmation distinguishes images going to the selected image folder from videos going to their independently configured destination. A known/configured target starts immediately. The browser is a storage-folder confirmation; it does not relocate the field/ref association.

**The sticky uploader remains the owner.** Its queue and progress UI are retained. Fields subscribe to the same state for waiting, upload, processing and failure feedback. Galleries aggregate their active batch. Removing a selection or accepting a newer replacement prevents an older completion from attaching itself later. The uploaded asset can still complete into the library.

## Configuration and shared scope

Image refs have Text & link, Image and Display sections. Video refs have Video, Playback and Display. File refs have Link & behavior and File. These use `Content.modal_sections` and the editor shell from `2439b502bf02797c316732a654d82974ece4a22d`, with ref-specific subtitles and a fixed Done footer.

Per-use caption, alternative text, credits, link, display classes and playback overrides survive replacement. Done returns to the editor; the footer explains when settings are included in saving the entry. Existing image crop/focal-point editing remains accessible. Ordinary image/file drawers explicitly identify their metadata as shared library details. Gallery-variable edits retain their existing gallery-resource persistence boundary.

The old picture “Dominant color” and video width/height inputs were removed from ref configuration because those fields are absent from their ref-data schemas and could not persist. Asset metadata and existing supported rendering controls remain available through their actual owners.

## Visual rounds

1. **Working intake:** shared field actions, populated drop targets and inline progress. The first pass made ordinary fields too prominent.
2. **Refs and galleries:** verified replacement and mixed intake, then inspected configuration on desktop and mobile.
3. **Modal review:** replaced the tall two-column picture configuration shown in review with the approved section rail. Applied the same shell to file/video refs.
4. **Control proportions:** refined drawer widths, metadata actions, video playback controls, gallery spacing and error wrapping. Compared 1440px desktop with 390px mobile.
5. **Quieter fields:** returned ordinary fields to the original compact thumbnail layout. Kept Configure and Browse library visible as a split control; revealed destination information during drag. Fixed the split control wrapping on mobile.

6. **Approved workspace comparison:** rebuilt the image drawer, contextual browsers and gallery variable against the current Assets and modal work on `next`, then iterated over fresh desktop/mobile captures and keyboard checks.

The [visual review](implementation.html) includes actual application screenshots, the supplied references, and links to the earlier rounds. Screenshots are browser captures of the E2E application, not design mockups. Its oversized blue fixture logo and consumer fonts are visible in full-screen evidence.

## Functional verification

The E2E consumer build passed after the final JS/CSS changes. Elixir formatting/compilation and `git diff --check` passed. Focused browser checks covered:

- Picture drop validation, destination Cancel/retry, replacement, per-ref overrides, save/reopen, and mobile Done visibility.
- A queued replacement completing after Remove without reattaching the image.
- Mixed image/video/image gallery order and save/reopen; mixed intake in the standalone gallery resource editor and gallery variable.
- File-ref upload, local settings, replacement and save/reopen.
- Video-ref replacement with playback/display overrides, and existing video picker selection with save/reopen.
- Image/file variable uploads, configuration, removal and save/reopen; entry image variables; ordinary file-field synchronization between editors.
- Existing image editor open/crop/copy/replacement paths; gallery selection, deselection and persistence.
- Image-library upload visibility/processing, file-library upload and shared replacement, populated Videos listing, and existing modal section/escape checks.

The second revision passed 12 distinct focused browser checks: the full image metadata/crop workflow, configured file/video selection, three ref/destination/gallery flows, five existing modal-design checks, gallery replacement, and video-picker save persistence. Desktop/mobile screenshot measurements confirm seven equal 48px playback rows. Grid and URL-input states were also inspected in the actual browser.

Nine AssetIntent tests and four upload-progress projection tests passed. Browser tests used real fixture bytes through file inputs and `DataTransfer`; no claim is made about physical Finder drags. Screenshots cover desktop and mobile, including active queue, drag destination and inline error states. The full run and targeted follow-ups are recorded in [E2E results](E2E-RESULTS.md).

Runtime checks also exposed and fixed a Videos-list preload error, stale image-library processing display, a default-config cancellation race, a gallery-variable creator-ID cast failure, and batched variable update ordering. The second pass also fixed Files filtering for serialized configuration targets; otherwise browsing from a configured file field disconnected the form. These fixes support the reviewed flows.

## Boundaries still present

- Remote S3 and external video-provider uploads require credentials and were not exercised live. Their existing adapters remain; provider transfers are still owned by their provider hooks.
- Generated image-editor copies retain their existing form-owned transport. This work does not claim that every upload route now has identical navigation recovery.
- A hard remount can leave a completed asset in the library without reattaching it to the original form. Mount-independent destination recovery is separate work.
- A mixed gallery batch containing an unsupported media type is rejected before upload; partial acceptance, Undo and Retry were proposals in the audit and are not implemented here.
- The existing browser shells are reused. This does not merge their asset-specific queries, result layouts or provider controls into one new browser.
- Shared input consumers inherit the changes, but every nested blueprint, transformer row and external consuming application was not separately exercised. No deployment was made.

## Implementation map

- [MediaField](../../../lib/brando_admin/components/assets/media_field.ex) owns presentation and action routing, with [scoped CSS](../../../assets/css/components/MediaField.css).
- [UploadTrigger](../../../assets/src/hooks/UploadTrigger/index.js) handles chooser/drop intake and destination confirmation. [uploadProgress](../../../assets/src/hooks/shared/uploadProgress.js) projects sticky state without owning transfers.
- [AssetIntent](../../../lib/brando/uploads/asset_intent.ex), [UploadManager](../../../lib/brando_admin/live/upload_manager.ex), and [Form hooks](../../../lib/brando_admin/live_view/form/hooks.ex) validate and deliver to the canonical owner.
- [MediaWorkspace styles](../../../assets/css/components/MediaWorkspace.css) adapt the existing Assets workspace to drawers and gallery dialogs.
- [Focused media-flow tests](../../../e2e/e2e/playwright/tests/blocks/block-media-fields.spec.js) cover the new cross-surface behavior.
