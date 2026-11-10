- `req_llm` is an optional dependency: a site without it runs with AI unavailable (no AI actions, alt text or meta description drafts, Write with AI or Assistant), and saves the memory its dependency tree takes.
  `mix igniter.upgrade brando` adds `{:req_llm, "~> 1.29"}` to `mix.exs` when the site's config sets AI up and it has no `req_llm`.
  A site that follows a Git branch, whose version does not change, gets nothing from the upgrade: add the line to `deps` in `mix.exs` and run `mix deps.get`, as the boot log and `mix brando.doctor` say when AI settings are present without it.
