- **Admin editor and Hex dependencies updated**. Tiptap 3.32.0, all
  `@tiptap/*` packages together so one `@tiptap/core` is locked,
  `@codemirror/view` 6.43.14 and DOMPurify 3.4.17 in BrandoJS; `req_llm`
  1.28 and Swoosh 1.29, with `decimal` 3.2, `llm_db` 2026.10.5 and
  `phoenix_pubsub` 2.4.1 that they bring. CI's actions move to
  `upload-artifact` v7, `download-artifact` v8, `setup-node` v7,
  `pnpm/action-setup` v6 and `codecov-action` v7, and Dependabot groups the
  `@tiptap/*` packages.
