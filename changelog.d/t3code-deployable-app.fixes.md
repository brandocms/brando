- **Media and logs of an installed application live outside the release.**
  `config/brando.exs` sets `media_path` and `log_dir` with `Path.expand`, which
  a Docker release build evaluates to the image's `/opt/app`.
  `mix brando.install` now writes `media_path: "./media"` and
  `log_dir: "./log"` to `config/prod.exs`, which resolve at runtime in the
  release directory where Florist links the persistent media. A literal path
  of the application's own, or one set in `config/runtime.exs`, is kept. See
  "Media and log paths" in the deployment guide.

- **`rerender_on_change` applies to fields typed in the form.** A preview
  target's `rerender_on_change` was read only for relation updates, so an
  edited entry field it lists, such as `language`, sent only `<main>` and left
  the header and footer as they were. A field listed for several assigns in
  `reassign_on_change` now refreshes all of them, not the first. A full render
  of a schema without block fields sends the whole document instead of
  `<main>`.

- **Asset sets and static-site builds survive deploys.** Without
  `:site_assets_path` or `:sites_path`, `site_assets/` and `sites/` were
  derived as the directory around `media_path`; with a relative
  `media_path: "./media"` in a Florist release that was the release directory,
  which the next deploy replaces and Florist later prunes. When the
  application runs as a release (`RELEASE_ROOT` is set), a media directory
  that is a symlink, as Florist's release `media` is, is now followed, so they
  are `<base>/site_assets` and `<base>/sites` beside the shared media. Outside
  a release, in development for instance, the link is not followed, so a
  checkout whose `media` links to another's keeps its own; configured roots
  are unchanged. Nothing is moved: sets and
  builds made before the upgrade stay recorded at their paths in the old
  release directory. A static-site build there can no longer be previewed,
  published or rolled back to, and a set there serves only until Florist
  prunes that release. After upgrading, upload and activate the frontend
  asset set again, run and publish a new static-site build, and share
  previews again (their captured sets are made anew). Copying an old release's
  `site_assets/` or `sites/` into the base directory does not help, since the
  records keep the old paths. On a server not deployed with Florist where
  `media` is a link to a mounted volume, the roots move the same way when
  running as a release, from beside the link to the volume's parent
  directory, and builds and sets stored under the old roots can no longer be
  previewed, deployed or pruned. To keep using them, set `:sites_path` and
  `:site_assets_path` to the old directories; otherwise rebuild and upload
  them again as above.
