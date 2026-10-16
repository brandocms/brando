- **The retired `install.sh` project skeleton is gone from
  `priv/templates/brando.install`.** No generator, upgrade or task wrote these
  files any more: the application files `mix phx.new` and `mix brando.install`
  now provide (`mix.exs`, `config/*.exs`, the endpoint, router, repo,
  telemetry, Gettext, `.formatter.exs`, `README.md`, `VERSION`, `.envrc`,
  `.gitignore`), the layouts, pages, partials, error and lockdown views
  `mix brando.gen.site` writes, `priv/repo/seeds.exs` (`mix brando.setup`
  seeds through `Brando.Setup.Seeds`), the Florist-managed `etc/logrotate`,
  `etc/systemd`, `rel/vm.args.eex` and media sync scripts, the old Cypress
  E2E setup, the frontend template's unused `pnpm-lock.yaml` and 116 stray
  copies of the upgrade migrations. `config/brando.exs` keeps only the
  `Brando.Images` block the installer reads. `etc/pgbkup.sh` stays for
  `pgbackup_enabled` (see the deployment guide). Anyone who copied a template
  from `deps/brando/priv/templates/brando.install` by hand should compare with
  a new Phoenix application that has `mix brando.install` instead (see the
  installation guide), and `Mix.Tasks.Brando.Install.render/1` no longer
  renders the removed paths.
