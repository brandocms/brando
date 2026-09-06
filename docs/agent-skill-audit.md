# Subsystem skill necessity audit

Issue #2701 proposed ten skills, incrementally. This audit checks those candidates
against `next` at `67191f96d`, existing guides, AGENTS.md, the block/upload skills,
and current source/tests. A subsystem name or a missing public guide does not
establish a need for a skill. Retain a skill only when it supplies task-specific
cross-component decisions or failure modes not already covered at a better home.

| Candidate | Decision | Evidence and reasoning |
| --- | --- | --- |
| Blueprint | No standalone skill | `guides/blueprints.md` already covers the DSL, traits, compiler/runtime split, queries, listings, and forms; `guides/blueprint_migrations.md` covers schema evolution. The proposed skill mostly shortened those instructions and listed source paths. |
| Media | Consolidate a source pointer into uploads | `.claude/skills/brando-uploads/SKILL.md` and `docs/UPLOADER.md` own intake/delivery; `guides/videos.md` covers providers. The useful additional seam is processing after delivery: point to the documented requeue guard in `lib/brando/images/processing.ex`, the Image/Vix processor, and drawer-close regression. Another routing skill would overlap uploads. |
| Admin forms | Retain, narrow to state coordination | Blueprint declarations are documented, but parent changesets, transformer streams, webhook delivery, and save collection cross different owners. `test/brando_admin/live_view/form/transformer_routing_test.exs` records a production failure caused by addressing the Form component ID instead of the HTML form ID. Form's one-time transformer collection initialization and pending nested changes need lifecycle guidance. Reuse AGENTS.md and the block/upload skills for their rules. |
| Live preview | Retain, narrow to internals | Form recovery and preview recovery arrive independently; `maybe_finish_live_preview_recovery/1` in Form coordinates their handshake. `test/brando_admin/live/form_recovery_test.exs` provides a general mounted-recovery harness, not a dedicated test of both preview event orders. Assign caches, HTML caches, reload transport, and ignored iframe DOM have different lifetimes. These maintenance decisions remain useful alongside an application configuration guide, including the configuration guide in #2770 for #2485. |
| Villain | No standalone skill | `.claude/skills/brando-blocks/SKILL.md` already owns block state, materialization, refs, rendering, and preview. `guides/villain_parser.md`, `guides/block_editor.md`, and `docs/FOOTNOTES.md` cover parser/rendering use. The candidate duplicated these boundaries. |
| Pages/navigation | Defer to developer documentation | `guides/pages.md` and `guides/navigation.md` are stubs. The candidate supplied a source tour and general cache/hierarchy cautions, not an additional proven workflow. Fill the public-guide gap tracked by #627; reconsider a skill only if a concrete maintenance failure needs guidance beyond those docs. |
| Sites/SEO | Defer to developer documentation | `guides/jsonld.md` and `guides/meta.md` provide existing coverage; identity, redirects, and sitemap recipes remain documentation work under #627. The candidate's context/cache index is not sufficient reason for a separate skill. |
| Admin listings | No standalone skill | `guides/blueprints.md` documents listing DSL; `guides/querying.md` explains queries; `guides/authorization.md` covers listing/export enforcement. The candidate mostly repeated these and generic selection-state advice without a distinct workflow. |
| Auth | No standalone skill | `guides/authorization.md` already documents modes, scopes, policies, revocation, boundaries, uploads, preview, and background execution. `docs/AUTHORIZATION.md` redirects there. A second set of security rules would create a competing source of truth. Session/onboarding gaps belong in developer docs. |
| Workers | No standalone skill | `Brando.Tenant.Job` documents tenant capture/restore at the enqueue/perform boundary; `guides/tenancy_and_environments.md` covers operations and `guides/authorization.md` covers execution-time reauthorization. Link to these contracts instead of maintaining a worker catalogue or duplicating their instructions. |

## Existing instructions reused

The block skill remains needed for the single-owner ops architecture. The upload
skill remains needed for the manager/browser/field ownership and transport
contracts. AGENTS.md already carries shared LiveView identity, sticky DOM, Ecto,
and validation rules. The two retained additions refer to these rather than
restating them. This audit does not retire unrelated deployment or project skills.

## Validation and future maintenance

The two new skills are intentionally maintenance-focused; neither substitutes
for a public developer guide. Check their relative links/source references and
YAML metadata, then compare each instruction with the named implementation and
regression. There is no application behavior change requiring runtime tests.

Revisit a decision when a concrete regression, repeated investigation, or an
architecture change demonstrates missing task-specific guidance. Prefer updating
the existing authoritative guide or skill before creating a new one.
