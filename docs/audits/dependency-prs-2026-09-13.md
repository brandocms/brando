# Dependency PR resolutions — 2026-09-13

Reviewed the original 15 dependency PRs and seven more opened by Dependabot during
cleanup. Seven were merged after reviewing their diffs and passing CI results;
15 were superseded by tested direct commits to `main`. No new PRs were created.

## Changes on main

- `42224a9fd`: isolate tenancy prompt tests from real terminal input. The module
  now owns and restores `Mix.shell()` in setup and runs synchronously because
  that setting is global. This fixes the terminal-only timeout hidden by CI's
  closed standard input.
- `5b85e1e6d`: preserve Manhattan's Elixir dependency updates and synchronize the
  shared entries in `e2e/mix.lock`. These include Dialyxir 1.4.8, Dotenvy 1.2.1,
  Erlex 0.2.9, Igniter 0.8.4, llm_db 2026.9.1, Mox 1.3.2, and ReqLLM 1.22.0.
- `458a7f24e`: migrate frontend consumers to Jupiter 5 beta.18/Motion, update both
  Playwright runners to 1.63.0, remove unused frontend-template/Playwright Yarn
  locks, and refresh applicable security fixes in the active backend pnpm locks.
- `1d3fbec69`: combine the overlapping frontend PostCSS, Vite 6, Babel, and
  brace-expansion updates from #2815–#2818.
- `39380d708`: upgrade all five Vite manifests to 8.3.0, their active lockfiles,
  the Svelte plugin to 7.3.0, and the frontend legacy plugin to 8.2.3. Also resolve
  the SystemJS, flatted, and Lodash updates from #2819–#2821.

## Jupiter, browsers, and build tooling

At review, Jupiter's npm `next` tag resolved to `5.0.0-beta.18`, while `latest`
still pointed to `3.48.4`. The frontend template and E2E frontend pin the beta.
The [Ses Optikk v6.0 frontend](https://github.com/tmjoen/ses_optikk/tree/v6.0/assets/frontend)
and Jupiter's [v5 changelog](https://github.com/brandocms/jupiter/blob/next/CHANGELOG.md)
provided the migration reference.

The menu uses Motion sequences, waits for animation completion before emitting
menu events, and prevents an interrupted close from hiding a reopened menu.
The E2E frontend initializes once after DOM readiness and handles pages without
mobile navigation. The new frontend smoke test covers these behaviors.

Vite 8.3.0 was verified against npm's `latest` tag. The root package already used
Vite 8; both templates and both E2E consumers still used Vite 6. The upgrade
replaces deprecated `rollupOptions` with `rolldownOptions`, removes the unsupported
`modules` target, aligns the E2E admin target with the template's `es2022`, and
renames Terser's `output` option to `format`. The last change fixes a real Vite 8
build failure caused by passing both Terser aliases. See the
[Vite 7](https://v7.vite.dev/guide/migration) and
[Vite 8 migration guides](https://vite.dev/guide/migration).

Older-browser compatibility is retained at the user's explicit request.
`@vitejs/plugin-legacy` 8.2.3 still depends on Babel 7; overriding that dependency
with Babel 8 would violate the plugin's declared range. Both modern and legacy
bundles are built and exercised. The asset manifests declare the supported Node
range `^20.19.0 || ^22.12.0 || >=24.0.0`; E2E Docker asset stages now use Node 22,
matching CI and the installation template.

Playwright 1.63.0 is installed in both active pnpm runners with matching Chromium.
The old #2807 changed an unused Yarn lock from 1.50.1 to 1.58.2; its failed module
reference duplication test passes locally on 1.63.0.

## PR disposition

| PR | Dependency | Resolution |
| --- | --- | --- |
| [#2787](https://github.com/brandocms/brando/pull/2787) | actions/checkout 7.0.1 | Merged. |
| [#2786](https://github.com/brandocms/brando/pull/2786) | actions/cache 6.1.0 | Merged. |
| [#2779](https://github.com/brandocms/brando/pull/2779) | Igniter 0.8.4 | Merged; shared E2E lock entry also synchronized. |
| [#2808](https://github.com/brandocms/brando/pull/2808) | js-yaml 4.3.2 | Merged into the active E2E frontend Yarn graph. |
| [#2806](https://github.com/brandocms/brando/pull/2806) | Browserslist 4.28.9 | Merged into the active E2E frontend Yarn graph. |
| [#2805](https://github.com/brandocms/brando/pull/2805) | Nanoid 3.3.19 | Merged into the active E2E frontend Yarn graph. |
| [#2804](https://github.com/brandocms/brando/pull/2804) | fast-uri 3.1.7 | Merged into the active E2E frontend Yarn graph. |
| [#2679](https://github.com/brandocms/brando/pull/2679) | Jupiter 4 beta.2 | Closed; frontend migration uses Jupiter 5 beta.18. |
| [#2807](https://github.com/brandocms/brando/pull/2807) | Playwright 1.58.2 | Closed; active runners use 1.63.0 and the unused Yarn lock is removed. |
| [#2758](https://github.com/brandocms/brando/pull/2758) | Browserslist | Closed; active root/backend pnpm graphs use 4.28.9. |
| [#2748](https://github.com/brandocms/brando/pull/2748) | Nanoid | Closed; active root/backend pnpm graphs use 3.3.19. |
| [#2725](https://github.com/brandocms/brando/pull/2725) | brace-expansion | Closed; active root/backend pnpm graphs use 1.1.18. |
| [#2710](https://github.com/brandocms/brando/pull/2710) | minimatch | Closed; active root/backend pnpm graphs use 3.1.5. |
| [#2706](https://github.com/brandocms/brando/pull/2706) | Rollup | Closed; active E2E backend first updated to 4.63.2, then moved to Rolldown with Vite 8. |
| [#2691](https://github.com/brandocms/brando/pull/2691) | markdown-it | Closed; absent from the active root/backend pnpm graphs. |
| [#2815](https://github.com/brandocms/brando/pull/2815) | PostCSS 8.5.23 | Closed; E2E frontend declares this minimum and locks 8.5.28. |
| [#2816](https://github.com/brandocms/brando/pull/2816) | brace-expansion 1.1.18 | Closed; implemented directly in E2E frontend. |
| [#2817](https://github.com/brandocms/brando/pull/2817) | Vite 6.4.3 | Closed; implemented directly, then upgraded to 8.3.0. |
| [#2818](https://github.com/brandocms/brando/pull/2818) | Babel core 7.29.7 | Closed; implemented directly and retained for the current legacy plugin. |
| [#2819](https://github.com/brandocms/brando/pull/2819) | Babel SystemJS transform 7.29.8 | Closed; covered by the current legacy plugin. |
| [#2820](https://github.com/brandocms/brando/pull/2820) | flatted 3.4.4 | Closed; implemented directly in E2E frontend. |
| [#2821](https://github.com/brandocms/brando/pull/2821) | Lodash 4.18.1 | Closed; implemented directly in E2E frontend. |

The six original backend-template PRs only changed a legacy Yarn lockfile that
is not copied by the installer manifest. Applicable fixes were applied to the
active pnpm graphs before closing them. This does not update or remove that
retained legacy graph; the Docker/package-manager migration remains tracked in
[#2814](https://github.com/brandocms/brando/issues/2814).

## Validation

- Full unit suite after merging upstream changes and the Elixir dependency
  updates: **2,392 checks passed** (135 doctests and 2,257 tests), 62.9 seconds,
  with `mix test --warnings-as-errors`.
- Frozen installs passed for the active root/backend pnpm graphs, the E2E
  frontend Yarn graph, and the generated frontend template consumer.
- Final Vite 8 production builds passed for both E2E consumers and both template
  consumers. Template checks used disposable consumers; the backend linked the
  local BrandoJS package. No standalone root asset build was used as a gate.
- **8 E2E tests passed** across module editing, navigation editing/public
  rendering, and frontend asset activation using the worktree's isolated database.
- **28 rich-text browser tests passed** with Playwright 1.63.0 and Vite 8.
- **4 generated frontend smoke runs passed**: modern and explicitly loaded legacy
  bundles, each with empty and populated navigation. These exercise the legacy
  code in Chromium, not a matrix of historical browser releases.
- Final E2E backend build: about 0.9 seconds. Final E2E frontend build: about
  1.8 seconds. These are local observations, not controlled benchmarks.

The full E2E suite, all four complete Igniter installation scenarios, and Docker
builds were not rerun locally. Existing Europa CSS processing warnings remain in
the generated frontend; this work did not migrate Europa's template syntax.
The admin Jupiter/GSAP imports and backend package-manager/Docker cleanup remain
separate work under #2814. The pre-existing block-editor audit was left untouched.
