- `brando_108` migrates Villain fragment blocks instead of stopping on a missing
  `content_blocks.fragment_id` column ([#3161](https://github.com/brandocms/brando/pull/3161)).
  If you have copied `brando_108` and `brando_119` but not run them, run `mix
  brando.migrations.check --update`.

- `brando_108` keeps a multi module block's own vars and datasource selection
  ([#3161](https://github.com/brandocms/brando/pull/3161)).

- File videos converted by `brando_133` keep looping and their cover placeholder, and a URL cover no
  longer prints as text ([#3161](https://github.com/brandocms/brando/pull/3161)).

- `brando_133` keeps legacy Vimeo and YouTube embeds saved with only a remote id, and each block's
  video shape ([#3161](https://github.com/brandocms/brando/pull/3161)).

- YouTube and Vimeo blocks honour their aspect ratio override
  ([#3161](https://github.com/brandocms/brando/pull/3161)).
