# Requirements Coverage (from `.claude/plans/form-audit/plan.md` § Phase 3 E + F)

Verified independently against the code; the plan's self-reported checkboxes were not taken at face value.

| # | Requirement | Status | Evidence |
|---|-------------|--------|----------|
| E1 | `assign_addon_statuses/1` → `assign_new`, with `has_meta?`/`has_alternates?` exceptions | MET | `form.ex:1437-1478`; `has_meta?` plain `assign` (`:1450`), `has_alternates?` plain (`:1458`) |
| E1b | Split out `assign_transformer_statuses/1` so transformer state is initialised once | MET | `form.ex:1466` guard clause `%{assigns: %{transformer_changesets: _}} -> socket` |
| E2 | Test `addon_statuses_test.exs`, 4 tests | MET | file present; 18 tests across the 5 new files pass (`mix test`, 0 failures) |
| E3 | `block.ex` container/fragment/palette copies scoped | **PARTIAL** | scoping exists (`block.ex:938-956`, `:1284-1285`) but the stated justification is **wrong** — see note below |
| E4 | `ComponentResolver.resolve/1` moved to `Dsl.transform_form/1` | MET | `dsl.ex:274-309`; call removed at `fieldset/field.ex:27` |
| E4b | Claim: `mix xref graph --sink .../input/vars.ex --label compile` lists nothing | MET (re-run) | ran it: **empty output**. No compile-dependency introduced |
| E5 | Test `component_resolution_test.exs` + rewritten third resolver test | MET | both files present and passing |
| E6 | `:languages`/`:admin_languages` → shared `Input.Options.expand/1`, not memoized | MET | new `input/options.ex:22-30`; `input.ex:288-289`; select/multi_select updated; `options_test.exs` mutates config |
| E7 | `block_field.ex` PubSub + `request_blocks_sync/1` gated on `connected?` | MET | `block_field.ex:653-662` (`subscribe_to_blocks/2`), `:676` (`&& connected?(socket)`) |
| E8 | `image_picker.ex` stops retaining the library in `socket.assigns.images` | MET | `image_picker.ex:93-113`, `assign_images/1` → `assign_config_target/1`, `list_images/1` now returns a list |
| E9 | `image_picker`/`video_picker` query bounding — marked `[ ]` | UNMET (correctly, by design) | no pagination/scoping in either; `FolderBrowser.folders_from_entries/2` still derives the tree — reason holds |
| E10 | Form-side `brando:image:<id>` subscriptions unsubscribe on `[:image, :error]` and on `:updated` **only when `:processed`** | MET (count claim wrong) | `hooks.ex:400-402` (error), `:429-431` (`%{id: id, status: :processed}`), called at `:321`. Claim "**eight** form-side subscribes" is off: there are **nine** — `form.ex:3550, 3993, 4785` + `hooks.ex:536, 556, 628, 653, 688, 717` (six in `deliver_asset/3`, not five). Each of the nine does sit ahead of a processing round, so the safety argument survives; only the arithmetic is wrong |
| F1 | Delete `forms/legacy.ex` + its `imports:` entry | MET | file deleted; `dsl.ex:272` verifiers-only; **zero** remaining `Forms.Legacy` refs in `lib/` or `test/` |
| F2 | Dead `handle_event("delete_selected", …)` in `input/gallery.ex` | MET | no `delete_selected` remains in any form input; surviving hits are unrelated listing code (`listing/hooks.ex:111`, `content/list.ex:1212`) |
| F3 | Remove the dead `mark_as_deleted` typo clause in `blocks.ex`; premise checked | MET | `blocks.ex:917-928`; premise confirmed — `changeset_runner.ex:45` matches `marked_as_deleted: true` and `mark_for_deletion/1` (`:105-115`) rewrites `action` to `:delete`/`:ignore` before `reject_deleted/2` runs. The typo'd clause was genuinely unreachable |
| F4 | Drop forced `Map.put(:action, :validate)`; verify `used_input?/1` and no top-level `.action` branch | MET | removed at `form.ex:898`, `:4942`, `:4952`, `:4959`. `deps/phoenix_live_view/.../phoenix_component.ex:1753` — `used_input?/1` = `used_param?(form.params, field)`, params only. Only `.action` read in the admin tree is `var_layout.ex:76` on nested `source.action in [:replace, :delete]` — no top-level branch |
| F5 | Test `empty_params_errors_test.exs`, 5 tests incl. touched-field control | MET | file present, passes |
| F6 | Seven inline `<svg>` → `<.icon>`; classes exist; dead CSS removed | MET | `form.ex:1977, 1988, 1996, 2004, 2012, 2019, 2024`. All seven classes present in `assets/css/heroicons.css` (`hero-tag`, `hero-clock`, `hero-calendar-days`, `hero-language`, `hero-eye`, `hero-arrow-top-right-on-square`, `hero-arrow-down-tray`). `svg path:nth-of-type(2)` removed (`Form.css:550-556`); no other rule depends on inline-svg structure in `.form-tab-builtins` — the surviving `svg { margin-top: 1px }` (`Form.css:602`) is scoped to `.form-tab-customs`, untouched. Visual result unverified (as the plan itself flags) |
| F7 | SKILL.md §10 "Position Response Tracker" drift corrected | MET | `SKILL.md:355`; `position_response`/`pending_positions` have zero hits in `lib/` or `assets/src/` |
| F8 | `form/tab.ex` `:if` — marked `[ ]`, attempted and reverted | UNMET (correctly) + MET on the recorded reasoning | `tab.ex:44-59` still `:if={@active_tab == @id}` (`:62`), with the reverted attempt, the failing spec line and the mechanism recorded above `tab_content/1`. Reason holds; the e2e claim itself was not re-run here |
| F9 | `polymorphic_embed` / `put_change/3` — resolved, no change needed | UNCLEAR | doc-only claim; the two removed sites and `link.ex`'s `has_one` were not re-verified within budget |

**Summary**: 17 MET · 1 PARTIAL · 2 UNMET-by-design · 1 UNCLEAR

---

## E3 — the one factual assertion that does not hold

The plan states: *"`container_config` is rendered by every root block (`render.ex:528`), not just containers, so scoping to `type == :container` alone would have broken the container select."*

That is **not what the code does**. `render.ex:528` sits inside `container/1` (`render.ex:451`), and `container/1` has exactly one caller: `render(%{type: :container} = assigns)` at `render.ex:197`, invoking `<.container` at `:200`. Confirmed by grep — there is no other `<.container` or `Render.container` call site in `lib/`. So `container_config` is rendered only by **root containers**, not by every root block.

Consequences:

- The `or belongs_to == :root` disjunct in `block.ex:940` and in `renders_palette_options?/1` (`block.ex:1284-1285`) is **redundant, not load-bearing**. Nothing would break if it were dropped.
- The stated performance win is therefore smaller than claimed: every root block of *any* type (module, fragment, module_entry, generic) still pulls the full `list_containers!` term and, via `maybe_assign_container/1`, the full palette list off ETS onto the LiveView heap. Only non-root, non-container **child** blocks were actually relieved.

Not a correctness defect — the scoping is over-broad in the safe direction — but the justification recorded in the code comment (`block.ex:934-936`) is inaccurate and would mislead the next reader who tries to tighten it.

## Scope check

Everything in `dsl.ex`, `legacy.ex`, `blocks.ex`, `block.ex`, `block_field.ex`, `fieldset/field.ex`, `input.ex`, `input/{options,select,multi_select}.ex`, `tab.ex`, `image_picker.ex`, `hooks.ex`, `Form.css` and the five new test files maps to a Phase 3 E/F item — commit `22007d023`.

Not Phase 3, but inside the `HEAD~5` range: `lib/brando/galleries.ex`, the `forget_unsaved_objects/1` addition in `form.ex:1244-1274`, and `test/.../input/gallery_test.exs`. These are commit `3739112a6`, the Phase 2 gallery fix, already reviewed under Phase 2. No unexplained changes found.
