- `mix brando.doctor` warns when Brando is a path dependency or an asset project takes an `@brandocms` npm package from a path outside the project, which a release build cannot see; in a production release it is an error. A Yalc copy is a warning once Brando has an npm release to switch to.
- `mix brando.doctor` warns while `.envrc.prod` or `.envrc.staging` still sets `PHX_HOST` to the placeholder `mix brando.install` writes without `--domain` (`my-app.com`, `staging.my-app.com`).
  Set `PHX_HOST` in them to the hosts the releases serve before deploying.
