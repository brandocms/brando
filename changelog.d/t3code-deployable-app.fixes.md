- `mix brando.install` sets `media_path: "./media"` and `log_dir: "./log"` in `config/prod.exs`, so
  a release keeps media and logs outside the image
  ([#3203](https://github.com/brandocms/brando/pull/3203)).

- `rerender_on_change` applies to fields typed in the form, and a field listed for several assigns
  in `reassign_on_change` refreshes all of them
  ([#3203](https://github.com/brandocms/brando/pull/3203)).

- In a release, asset sets and static-site builds are stored beside the shared media directory, so
  they survive deploys ([#3203](https://github.com/brandocms/brando/pull/3203)).
  After upgrading, upload and activate the frontend asset set again, run and publish a new
  static-site build, and share previews again.
  On a server not deployed with Florist whose `media` links to a mounted volume, set `:sites_path`
  and `:site_assets_path` to the old directories to keep using what is stored there.
