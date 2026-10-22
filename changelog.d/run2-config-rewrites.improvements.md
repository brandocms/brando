- `mix brando.migrate54` adds the `Phoenix.CodeReloader` listener to `mix.exs`, replaces `use
  Mix.Config` with `import Config`, and changes Logger's `:warn` level to `:warning`
  ([#3167](https://github.com/brandocms/brando/pull/3167)).
