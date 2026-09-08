# Media upload experience audit

8 September 2026 · Brando `f7276d594` · audit and proposals, before implementation

> **Implementation review:** The agreed direction has now been implemented and iterated in the E2E app. See the [visual review](implementation.html) and [implementation / verification record](IMPLEMENTATION.md). This document preserves the original findings and proposals; they are not a description of the current worktree.

## Finding

Brando already shares much of its upload engine, but it does not yet share an interaction model. The same apparent action can open the system file chooser, an asset drawer, a block configuration modal, a variable modal, or a library drawer. Drag and drop depends on both the context and whether it already contains an asset.

The intended contract should be simple: **drop onto the field you want to fill; Upload opens the system chooser; Browse library selects existing media; Configure opens that use's settings.** A populated field must remain a drop target. Galleries add; single fields replace their association. Keep the existing sticky upload progress component; optional field progress supplements it.

## Scope and evidence

Source inspection covers blueprint fields and their nested/meta/avatar/logo uses; picture, file, video and gallery refs; block and entry variables; selection drawers; resource listings; the image editor; transformer intake; the sticky queue; and provider-video adapters.

The browser evidence is recorded in the [37-screenshot gallery](screenshots.html) and [machine-readable manifest](evidence.json). Full desktop screenshots are 1440 × 1000; mobile screenshots are 390 × 844. One gallery-field detail is an element crop. Provider uploads require configured external services and are source-reviewed separately. The E2E app uses local fixture media; observations are not claims about production storage performance. No production application behavior was changed during this audit.

## Verified findings and priority

| Priority | Reproduced behavior | Evidence |
| --- | --- | --- |
| High | Visible image form field does not accept drops; Image drawer preview does. | [Field](screenshots/01-project-fields-empty.png), [drawer](screenshots/05-image-drawer-populated.png). Instrumented outer drop made zero enqueue calls; drawer drop delivered an image. |
| High | Populated picture ref has no visible upload handler; a replacement drop leaves it unchanged. | [Empty](screenshots/16-picture-ref-empty.png), [populated](screenshots/18-picture-ref-populated.png). |
| High | Gallery block's advertised empty drop area does nothing. Dropping on its toolbar wrapper works. | [Drop message](screenshots/21-gallery-ref-empty.png), [successful toolbar-area drop](screenshots/22-gallery-ref-populated.png). |
| High | Gallery field accepts images on its main surface but rejects a dropped video as an unsupported image. | [Controls](screenshots/39-gallery-field-detail.png), [error](screenshots/14-gallery-field-video-drop-error.png). |
| High | Videos listing returns HTTP 500 after local-video upload. | [Error screen](screenshots/37-videos-library.png). Server reports `KeyError: key :filename not found in Ecto.Association.NotLoaded`, at [video.ex:155](../../../lib/brando/videos/video.ex#L155). This is a reproduced correctness defect, not a proposed design change. |
| High | Image drawer is wider than a 390px viewport. | [Mobile drawer](screenshots/40-image-field-drawer-mobile.png). Measured width 425px, x = −35px; left title and controls clip. |
| Medium | Image picker says to upload but offers no intake; video picker does. | [Image picker](screenshots/03-image-picker-empty.png), [video picker](screenshots/11-video-picker.png). Image picker had zero file inputs. |
| Medium | Image variables remove the upload input after selection. Gallery variables and the standalone gallery resource editor have no direct uploader. | [Populated image variable](screenshots/24-image-var-modal-populated.png), [gallery variable](screenshots/32-gallery-var-modal.png), [resource editor](screenshots/41-gallery-resource-editor.png). |
| Medium | Image library root upload succeeds into the configured default folder, leaving the visible root empty. | [Success in empty root](screenshots/34-images-library-uploaded.png), [asset found in site/default](screenshots/38-images-library-default-folder.png). Show the effective destination before intake. |
| Medium | Rejected image file preserves the existing image, but the only error is clipped in the floating queue. | [Rejected PDF](screenshots/06-image-rejected-file.png). The screenshot also shows the queue overlapping editor space. |

**Positive checks:** image, PDF and local-video intake delivered to their fields; a picture ref, gallery image and image variable remained present after saving and reopening the audit page. The reopened image picker marked the current variable image selected. File library replacement already explains its shared scope clearly. These behaviors should survive the redesign.

**Method limits:** drops were exercised with real fixture bytes in browser `DataTransfer` events, rather than physical Finder drags. Native chooser opening was observed through Playwright's chooser event. Fixture uploads are small and local; no transfer-duration, large-batch, cancellation, hard-reload or remote-provider claims are made. No automated full suite was run for this audit. The E2E consumer asset build passed with existing bundle/Browserslist warnings. File refs, transformer runtime, provider uploads and gallery object replacement were source-reviewed where not represented by a screenshot. Nested consumers were assessed through their shared input implementation; individual nested usages were not all exercised in the browser. The Videos page could only be captured in its failing state; no normal populated Videos-list screenshot is claimed.

## Design basis

This proposal extends the [approved admin UI direction](../../admin-ui-design.md), including its Utilities references and the approved modal decisions from 8 September. The shared asset browsers and contextual editor shell are the visual starting points for this work.

- Retain the approved **Section rail** shell for media settings with distinct sections, using `Content.modal` / `Content.modal_sections`. Simple settings need no artificial rail. Keep **Done** where editing already updates the parent form.
- Reuse the current asset-browser layout and components for selection inside the approved dialog shell. The guide's split-workspace approval concerns link picking; it is not a requirement to replace the existing asset browser with a new three-column design.
- Use the existing Main typefaces, the approved ink/muted/border/accent roles, compact 5px-radius secondary controls, 8px label gaps, and a deliberate 16/24px spacing rhythm. Preserve useful whitespace without oversized empty canvases.
- The inline interaction study uses the actual E2E Main regular/medium fonts and approved light palette. Its small library/settings panels demonstrate action routing; they are not replacements for the approved production modal shell. Dark colors are study adaptations, not a newly approved Brando theme. Implementation still needs comparison at 1440px and 390px with the consuming application's fonts.

## Visual assessment

- Equivalent media tasks use a dark narrow drawer, a light wide folder drawer, a centered light modal, or a large inline canvas. The visual transition is larger than the task requires.
- Empty-state icons occupy hundreds of pixels in some block and modal contexts, while field actions and generated filenames are tiny. A file variable even uses the image icon. Use the actual media type's icon and let the preview, name and action establish hierarchy.
- Displayed image names are generated storage filenames; paths and config targets consume prominent space. Keep technical data in details, and provide a useful asset name as the primary label.
- Actions alternate between Add, Select, Pick, Upload, Reset and Replace; some first open an editor, some a picker. Reuse verbs according to the action they perform.
- Mobile is not just a scaled desktop: the 425px image drawer clips, and the image-variable path wraps across its two-column divider. Stack preview and controls deliberately and constrain drawers to the viewport.
- Newer resource lists and the file replacement modal already offer a calmer direction. Reuse their restrained borders, compact controls, clear explanatory text and the approved admin palette.

## Surface inventory

| Surface | Entry and editing flow in current source | Drop boundary | Upload ownership |
| --- | --- | --- | --- |
| Blueprint image field | Add/Edit image → Image drawer. Upload image → OS chooser. Select existing image → image picker. Edit/Crop → another drawer. | Preview inside Image drawer; outer form field has no UploadTrigger. | Sticky manager; entry-field adapter. |
| Nested image fields, metadata, avatar, logo, SEO fallback | Reuse Input.Image, so inherit the same outer-field gap. | Same as image field. | Same adapter with field path/configuration. |
| Picture ref, empty | Click canvas → OS chooser; default configuration then asks for folder. Pick an existing image → block configuration → Select image → picker. | Empty canvas and empty config preview. | Sticky manager; picture-ref adapter. |
| Picture ref, populated | Preview/Edit image → block config; pencil/Edit-Crop → image editor; Select image → picker. | Visible preview has no uploader; empty upload canvas is hidden. | Existing ref ownership retained. |
| Image variable (block or entry) | Add/Edit image → variable modal → upload canvas or Select image → picker. | Only the empty modal contains UploadTrigger; outer variable field and populated modal do not. | Manager supports block_var and entry_var. |
| Blueprint file field | Add/Edit file → File drawer → Upload file or Select existing file → picker. | File drawer preview, not outer field. | Sticky manager; entry-field adapter. |
| File ref | Browse files → picker directly; Upload a new file → block config → canvas. Populated file → context editor → Replace file → picker. | Only empty config preview. | Sticky manager; file-ref adapter. |
| File variable | Add/Edit file → variable modal → upload canvas or Select file → picker. | Only empty modal. | Sticky manager; variable adapter. |
| Blueprint video field | Add/Edit video → Video drawer, with Upload/File and external-URL tabs; existing video opens picker. | Local upload control only; outer field has none. Provider inputs differ. | Manager for local/S3; hook-owned provider transfer. |
| Video ref or variable | Selection and replacement through video picker; ref adds playback and cover-image configuration. | No direct drop surface on ref/variable. | VideoPicker dispatches local/S3 or provider upload. |
| Blueprint gallery field | Upload images, Upload videos where enabled, Select images, Select videos. Inline collection editing. | Outer wrapper routes to image intake; nested video upload control routes to video. Mixed files do not share a classifier. | Manager; gallery adapter. |
| Gallery ref | Upload images, Select images, Select videos. Config/edit controls for objects. | Upload hook wraps button strip; empty-state drop message and populated objects are outside it. | Manager for images; video picker for videos. |
| Gallery variable | Modal with Add images/Add videos, per-object Remove, Reset gallery. | No upload/drop trigger in modal; image picker is selection-only. | Delivery adapters exist, but image upload entry is absent in this UI. |
| Gallery resource editor | Select images or Select videos → picker; collection provides reordering and removal. | No upload trigger on the collection; drag is for reordering. | Selection through Input.GalleryObjects. |
| Images/Files resource lists | Folder browser and Upload control. | Native LiveView drop target on toolbar upload form. | Listing-owned allow_upload; bypasses sticky manager. |
| Videos resource list | Folder browser and record edit/create UI. | No shared listing upload zone; runtime listing failed after local upload (see verified findings). | Video upload remains in field/picker UI. |
| Shared image/file pickers | Folder-aware selection and organization. | Library-item organization is distinct from OS-file upload; no external-file intake control. | Selection, not upload. |
| Shared video picker | Folder-aware selection plus Upload file and Add from URL. | Upload control only for local/S3; provider hook differs. | Manager or provider adapter. |
| File library “Replace file” | Explicit dialog explains replacement everywhere while preserving URL. | Dialog drop zone + Choose file. | Manager file_replace intent; same-extension and single-file rules. |
| Image editor | Crop/focal operations; Save changes versus Save as new copy. | Generated canvas image, not an ordinary field drop. | Crop replacement uses HTTP; new copy still uses form-owned image_editor_upload. |
| Transformer subform | Mixed image/video intake creates ordered placeholders, then editable entries. | Whole transformer uploader. Individual existing asset rows use selection controls. | Images/local/S3 via manager; provider hooks report to queue. |

## Why the experience feels inconsistent

### The label does not reliably predict the next surface

An empty picture ref treats its canvas as Upload. A blueprint field treats Add image as Open editor. A variable treats Add image as Open modal. “Pick an existing image” on a picture ref takes an additional config step before the picker. This increases both clicks and uncertainty.

### Drop support disappears when it becomes most useful

Replacement is a common editing action, but populated picture refs and image/file variables remove or hide their upload target. Ordinary fields never offer one at their visible form location. A user cannot learn “drop onto an image” and carry that knowledge between surfaces or states.

### Some instructions promise an action their target cannot handle

The gallery block's empty-state message lies outside its upload hook. The image picker empty state says “Upload files here or choose another folder” but the picker has no new-file intake control. These are functional/discoverability issues, beyond visual polish.

### Media collections have separate intake rules

Gallery image and video actions are split. The broad image wrapper routes dropped files as images. The block gallery invites “media” but its trigger accepts images. TransformerUploader already demonstrates mixed-type routing and ordered placeholders; that behavior can be reused conceptually without changing ownership of gallery state.

### Progress is shared only on some paths

UploadManager offers queued/uploading/processing/done/error and cancellation for non-provider transfers, but listing uploads and image-editor new copies bypass it. Provider hooks report into it while retaining ownership of their transfers and are aborted when their hook is destroyed. Visibility in the shared queue therefore does not imply identical navigation survival. The current queue names files, with a var key available only as a title tooltip; it does not clearly identify the destination field for all contexts, and provides dismissal rather than a Retry action.

### “Replace” describes two different operations

Replacing a field/ref association should select a different asset for this use. File library Replace file overwrites the existing resource everywhere while preserving its identity/URL. Image editor Save changes also deserves an explicit scope. These operations need distinct labels and consequences; a drag onto a field must never silently become an overwrite of a shared asset.

## Direction after review

The discussion establishes five constraints: preserve the existing sticky upload UI; preserve per-use configuration; reuse the newer asset browsers; support drops on empty and populated media fields; and follow the approved admin design. **Direct field actions remain the recommended interaction model.** Destination confirmation, replacement recovery and gallery selection details below are proposals to resolve before implementation.

### One browser, used in different contexts

The Images, Files and Videos resource pages and their field pickers already use [Assets.FileBrowser](../../../lib/brando_admin/components/assets/file_browser.ex) for breadcrumbs, recent folders, folder navigation, folder creation and the main content area. The remaining duplication is in results, action toolbars, selection and upload wiring: resource pages render `Content.List` with schema listing rows, while pickers render their own rows/grids and media-specific toolbars.

Consolidate those pieces around the newer resource-browser design:

| Context | Shared components | Purpose-specific behavior |
| --- | --- | --- |
| Asset library page | Folder navigation, search, ordering, asset previews/metadata, counts, empty/loading states and upload controls | Manage library assets and permitted resource-level actions |
| Browse library from a field/ref/var/gallery | The same browser UI within the approved dialog shell | Show compatible assets and the current unsaved selection; deliver the choice to the originating context |
| Choose upload destination | The same folder navigation and creation controls | Show pending files and the receiving field/ref; confirm Upload here |

Share components and query/filter rules with explicit context parameters. Keep navigation inside an unsaved editor local to that browser instance; opening the standalone Assets route would abandon the task context. Search, counts and selectable results must use the same permitted scope. Reuse row/card presentation, with media-specific previews and useful grid/list views. Configured restrictions and organization permissions apply in each context.

### Field actions and drop behavior

| Surface | Visible actions | External-file drop |
| --- | --- | --- |
| Empty image/file/video field, ref or variable | Upload; Browse library; Add from URL for video where supported | Fill this exact field after intake and any required destination confirmation |
| Populated single field, ref or variable | Configure; Replace; Remove | Replace this use's asset association; keep this surface droppable |
| Empty or populated gallery | Upload; Browse library; existing gallery settings and per-item Configure/Replace/Remove where supported | Add permitted media to the collection; an item's explicit Replace action changes that item |

**Upload** opens the system chooser. **Browse library** opens the shared browser in selection mode. **Configure** opens the owning field/ref/var editor directly, preserving the approved section rail where useful. Keep configuration available before selecting an asset wherever the current context supports meaningful settings in that state. **Replace** offers Upload replacement and Browse library; keyboard users need both routes as well as the direct drop gesture.

Files chosen through the system chooser and files dropped on a field follow the same upload validation and destination rules. Selecting an existing library asset checks compatibility and changes the association; it does not move that asset or ask for an upload destination. On selection, return to the originating editor and section with pending form values intact.

Gallery intake classifies each file and uses that media type's configuration. An image-only gallery must say “Drop images to add”; a gallery accepting both types may say “Drop images or videos to add.” Images and videos can have different limits and destinations. Keep batch order deterministic and report rejected items individually. Single-value fields reject a multi-file drop clearly before changing their value. Apply the collection treatment to gallery fields, refs, variables and the standalone gallery resource editor.

External-file drag feedback must be distinct from block/gallery reordering and moving library assets between folders. Nested drop targets must produce one upload request for the intended field. Keep Configure, Replace and Remove available without hover, and retain video URL/provider options wherever the configuration permits them.

### Destination confirmation — recommended policy

A drop identifies **where the asset will be used**, such as “Hero → Main image”. The **library folder** is a separate choice. Physical storage is resolved by the upload configuration and transport; a library folder must not imply that every provider supports an equivalent storage path.

- **Configured destination, explicit browser folder, or a folder already confirmed for this target/configuration in the current editor session:** show the effective folder beside the field and begin uploading after validation. A browser's ambiguous Root view does not count as an explicit upload destination.
- **Only a default/recent suggestion is available:** hold the files and open a compact confirmation containing preview/file count, receiving field/ref, effective library folder, Change where permitted, Upload here and Cancel. Reuse the existing browser's folder controls. No transfer starts before confirmation.
- **Mixed gallery with different image/video destinations:** show the resolved destination for each group when confirmation is needed. Do not apply the image folder/configuration to video by default.

Always validate the effective target and folder on the server. Reuse is scoped to the target and configuration; a configuration or permission change invalidates the earlier choice. Recent folders are suggestions, not confirmation for another field. Dismissing the pending confirmation cancels that pending intake, leaving the field untouched. Once an upload has started, cancellation belongs to the sticky manager; moving a completed asset is a separate library action.

### Preserve progress, configuration and save ownership

**Sticky progress stays.** The existing UploadManager and its progress UI remain central. Optional progress inside a field mirrors the same upload through scoped notifications keyed by upload identity and destination. This needs additional wiring; it must not introduce a second transfer owner or repeatedly rebuild/validate the parent form. A field disappearing must not cancel a manager-owned transfer. Preserve the current queue and refine clipped errors or destination labels within it.

**Configure stays contextual.** Preserve each ref's explicit caption, alt, credits, link, fetch priority and other supported overrides, along with its effective upload configuration. The same image can remain configured differently in two refs. On replacement, explicit overrides survive; inherited values should continue to inherit from the newly selected asset instead of becoming frozen copies of the old defaults. Keep Edit/Crop accessible and explain its actual scope. Review source-dependent crop/focal choices when replacing an image; do not label a shared asset edit as a local override. Plain blueprint fields retain their existing metadata scope.

**Asset delivery and saving are separate.** Keep the old association until a replacement is successfully stored and delivered to the owning adapter. Images currently enter processing after that delivery, so Processing and Ready must remain distinct. A later processing failure needs a recoverable previous image; it must not be described as an intake rejection that never changed the field. Configure's Done retains the current parent-form semantics. Upload completion does not mean the entry has been saved.

**Replacement and removal affect this use.** Ordinary drops and picker choices never overwrite the shared source resource. Remove clears the association. The proposed Undo restores the previous association and leaves the newly uploaded asset in the library; it is not asset deletion. Library Replace file retains its explicit resource-wide meaning and URL-preservation rules.

**Delivery must still belong to the current request.** If the user selects another asset, removes the field/ref, or starts a later replacement while an upload is pending, an older completion must not overwrite the newer choice. Correlate delivery with the current target/request, as well as upload identity. Keep the established field/ref/var/gallery adapters and block commit boundary; the shared browser does not own those edits.

**Errors and retries must describe the real operation.** Intake/transfer rejection preserves the previous association. Processing failure acts on an asset already created. A future Retry upload can reuse retained bytes or ask the user to choose the file again; Retry processing must reuse the existing asset and avoid duplicate records. Retry and field progress are additions to evaluate, not capabilities claimed for the current component.

### Implementation gaps confirmed in source

These are engineering boundaries to address and test, separate from the browser-reproduced findings above:

- **Transfer survival does not guarantee field attachment.** The manager delivers to a form-mount-specific topic. After remount, an asset can finish in the library while its original field no longer receives the delivery. A field progress subscription alone does not fix this. Preserve library availability and report attachment truthfully; remount recovery needs deliberate handling. See [manager delivery](../../../lib/brando_admin/live/upload_manager.ex#L669).
- **Provider transfers still have separate ownership.** Provider hooks report into the sticky queue but abort when their owning hook is destroyed. Reusing the browser shell does not change this. Moving provider ownership into the sticky lifecycle, if included, requires a separate adapter change and transport tests; do not promise uniform navigation survival before that work.
- **Folder and storage-path handling differ by media type.** The manager's [upload-path override](../../../lib/brando_admin/live/upload_manager.ex#L812) is image-specific; direct file/video keys come from their configured upload path. A common destination UI must resolve each transport's supported library/storage behavior before offering Change. Do not silently reuse the image implementation for every media type.
- **Library uploads and generated image copies are existing exceptions.** Images/Files resource uploads use listing-owned `allow_upload`; image-editor new copies use a form upload. New upload entry points must use the canonical manager boundary. Migrating library uploads needs an explicit library-only intent in [AssetIntent](../../../lib/brando/uploads/asset_intent.ex); do not invent a field target to make library uploads work. Generated image-copy migration is a separate image-editor follow-up.

## Decisions still open

| Decision | Recommendation to review |
| --- | --- |
| Destination confirmation | Use the conditional policy above; reuse a confirmed destination only within the current target/configuration/editor session |
| Replacement recovery | Offer association Undo before entry save; define source-dependent crop handling and prevent older uploads from overwriting newer choices |
| Saving with uploads pending | Preserve existing save safeguards while inspecting each context; make pending upload/attachment explicit so Save cannot appear to include an asset it has not received |
| Gallery library selection | Preserve current immediate-selection semantics initially; introduce Add N items / Cancel only with real pending selection and commit behavior |
| First implementation scope | Images across fields/refs/vars plus shared image browsing first; files/videos and all gallery contexts next; provider ownership and generated-copy migrations tracked explicitly |

These are remaining product/implementation choices, not approvals already given. The early interaction sketch demonstrates direct actions only: its simplified browser/settings panels, omitted sticky queue, sample format/size limits and dark adaptation are not a production specification. This document's preservation and reuse requirements govern the next design pass.

## Implementation sequence after agreement

1. Review actual empty, populated, drag-hover, pending-destination, uploading/processing and error states at 1440px and 390px, with the existing sticky upload component visible. Resolve the open decisions above using the current browser and modal designs.
2. Build the shared image field surface and intake behavior through `AssetIntent` / `ConfigTarget`; apply to blueprint fields, picture refs and image variables, including populated and nested uses. Integrate the existing image browser in selection mode during this first pass. Share its result presentation and upload control; use a canonical library-only intent for resource-page uploads. Preserve Configure and each context's state ownership.
3. Extend the same contract to files and videos, retaining allowed URL/provider routes and truthful transport behavior. Reuse browser components and resolve destination semantics per media type. If field progress is included, mirror the manager through scoped notifications and verify it against the sticky display.
4. Extend the collection surface to gallery fields/refs/vars and the gallery resource editor, including mixed-type routing, deterministic order, partial failures and distinct add/replace/reorder actions. Keep image/video configuration separate.
5. Complete the explicitly scoped transport work: provider lifecycle migration if chosen and generated image-copy migration as its own follow-up. Preserve the working sticky UI throughout. Address the reproduced Videos-list failure and mobile clipping as focused fixes alongside the affected surfaces.
6. Run focused regression checks at each phase. Verify drop/chooser/picker/replace/remove → save → reopen; two refs with different overrides using the same image; inherited versus explicit metadata; failed and superseded replacements; sticky progress with the originating field present/absent; scoped destination confirmation and cancellation; mobile, keyboard and nested-dialog focus; allowed storage/provider variants.

Existing coverage to preserve includes [image library browsing](../../../e2e/e2e/playwright/tests/assets/images.spec.js), [file resource replacement](../../../e2e/e2e/playwright/tests/assets/files.spec.js), [video folder metadata](../../../e2e/e2e/playwright/tests/assets/videos.spec.js), [block variable uploads](../../../e2e/e2e/playwright/tests/blocks/block-var-uploads.spec.js), [entry variable persistence](../../../e2e/e2e/playwright/tests/pages/page-vars-upload.spec.js), [gallery remove/add persistence](../../../e2e/e2e/playwright/tests/blocks/block-gallery-image-replace.spec.js), [file synchronization between editors](../../../e2e/e2e/playwright/tests/projects/file-field-sync.spec.js) and [modal behavior](../../../e2e/e2e/playwright/tests/modal-design.spec.js). Extend the relevant tests for new drop/replacement states. These tests were identified for implementation validation; this document review did not run them.

## Source map

- [Shared trigger](../../../assets/src/hooks/UploadTrigger/index.js), especially intake, target forwarding, drop listeners and folder confirmation.
- [Image field](../../../lib/brando_admin/components/form/input/image.ex) and [Image drawer](../../../lib/brando_admin/components/form/image_drawer.ex).
- [Picture ref](../../../lib/brando_admin/components/form/input/blocks/picture_block.ex), [file ref](../../../lib/brando_admin/components/form/input/blocks/file_block.ex), [video ref](../../../lib/brando_admin/components/form/input/blocks/video_block.ex), [gallery ref](../../../lib/brando_admin/components/form/input/blocks/gallery_block.ex).
- [Variable rendering and modals](../../../lib/brando_admin/components/form/input/blocks/render_var.ex), shared by entry and block variables.
- [Gallery resource collection](../../../lib/brando_admin/components/form/input/gallery_objects.ex).
- [Gallery field](../../../lib/brando_admin/components/form/input/gallery.ex), [file drawer](../../../lib/brando_admin/components/form/file_drawer.ex), [video drawer](../../../lib/brando_admin/components/form/video_drawer.ex).
- [Image picker](../../../lib/brando_admin/components/image_picker.ex), [file picker](../../../lib/brando_admin/components/file_picker.ex), [video picker](../../../lib/brando_admin/components/video_picker.ex).
- [Images listing](../../../lib/brando_admin/live/images/image_list_live.ex), [files listing and shared replacement](../../../lib/brando_admin/live/files/file_list_live.ex), [videos listing](../../../lib/brando_admin/live/videos/video_list_live.ex).
- [Manager](../../../lib/brando_admin/live/upload_manager.ex), [provider hook lifecycle](../../../assets/src/hooks/shared/providerVideoUploader.js), [transformer intake](../../../assets/src/hooks/TransformerUploader/index.js).
- [Image editor](../../../assets/src/hooks/ImageEditor/index.js) and [form-owned image-editor upload](../../../lib/brando_admin/components/form.ex).

The historical migration narrative in [UPLOADER.md](../../UPLOADER.md) is useful context but is not a current surface inventory: blanket statements about every upload being migrated must be reconciled against the listing and image-editor paths above.
