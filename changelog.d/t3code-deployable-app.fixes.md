- **Media and logs of an installed application live outside the release.**
  `config/brando.exs` sets `media_path` and `log_dir` with `Path.expand`, which
  a Docker release build evaluates to the image's `/opt/app`.
  `mix brando.install` now writes `media_path: "./media"` and
  `log_dir: "./log"` to `config/prod.exs`, which resolve at runtime in the
  release directory where Florist links the persistent media. A literal path
  of the application's own, or one set in `config/runtime.exs`, is kept. See
  "Media and log paths" in the deployment guide.
