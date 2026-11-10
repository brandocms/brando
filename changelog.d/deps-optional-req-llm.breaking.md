- `req_llm` is an optional dependency: a site without it runs with AI unavailable (no AI actions, alt text or meta description drafts, Write with AI or Assistant), and saves the memory its dependency tree takes.
  A site that uses AI adds it to `deps` in `mix.exs` and runs `mix deps.get`:
  `{:req_llm, "~> 1.29"}`. `mix brando.doctor` and the boot log warn when AI settings are present without it.
