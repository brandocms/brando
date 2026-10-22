- Content SEO counts a cover image as a sharing image again
  ([#3172](https://github.com/brandocms/brando/pull/3172)).

- `mix brando.images.adopt`, the doctor and Utilities no longer recommend recreating every image
  when the media folder has no image files ([#3172](https://github.com/brandocms/brando/pull/3172)).

- The doctor's robots.txt check warns only about a `priv/static/robots.txt` that the endpoint's
  `Plug.Static` serves ([#3172](https://github.com/brandocms/brando/pull/3172)).

- An image whose `config_target` field is gone logs one line per target, where it logged the whole
  image with a stacktrace ([#3172](https://github.com/brandocms/brando/pull/3172)).

- `mix brando.gen.blueprint_migration` lists the Blueprints it will write by name and hash
  ([#3172](https://github.com/brandocms/brando/pull/3172)).
