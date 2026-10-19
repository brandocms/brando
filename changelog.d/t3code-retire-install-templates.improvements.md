- The retired `install.sh` project skeleton is removed from `priv/templates/brando.install`, and
  `Mix.Tasks.Brando.Install.render/1` no longer renders its paths
  ([#3205](https://github.com/brandocms/brando/pull/3205)).
  If you copied a template from `deps/brando/priv/templates/brando.install` by hand, compare it with
  a new Phoenix application that has run `mix brando.install`.
