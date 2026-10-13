- **Legacy pictures and gallery images without an image row survive the
  blocks conversion.** `brando_133` linked a Villain picture ref to an image
  by `path` only, among images not in the trash, and then stripped `path`,
  `sizes`, `width` and `height` from every picture ref, linked or not. A
  picture whose row was deleted (0.53 showed it from the ref's own data)
  became an empty picture, and a gallery dropped such images. It now matches
  a picture by its `sizes` first, as it does gallery images, then by `path`;
  makes the image row from the legacy data (path and sizes without the media
  prefix, dimensions, formats, dominant color, focal point) when no live row
  matches, for pictures and gallery images alike; and leaves the data on a
  ref it could not link. Each gallery ref also gets a gallery of its own:
  galleries were paired with refs by creation order among every `default`
  gallery, so two refs with the same uid, or a gallery already there, shifted
  every later ref onto the wrong gallery. Sites that ran the old `brando_133`
  repair theirs with `mix brando.repair.legacy_media` (see Features), before
  dropping the Villain columns.

- **`mix brando.check.legacy_conversion` notices media refs that lost their
  media.** It compared ref names only, so a picture left without its image
  passed as "came through". A picture whose Villain data had a `path` now
  needs an image, a gallery as many images as Villain listed, and a video
  with a URL or remote id a video: `pages #2 › block 3 (module "Jobb med
  oss") › ref pic: legacy image images/site/posts/1n60vo3o9p06.jpg has no
  image now (lost in the conversion, or removed by an editor since)`. A ref
  that showed nothing on 0.53 is not a loss.

- **Multi module code reads its entries' vars again.** Module code stored in
  the database that reads its entries the 0.53 way,
  `{% for link in entries %}{{ link.data.vars.url }}{% endfor %}`, rendered
  nothing after the blocks conversion: an entry is a block now, with its vars
  at `link.vars.url` and its refs at `link.refs`. `brando_219` rewrites, in
  every environment, a loop variable over `entries`, a variable assigned an
  entry (`entries.first`, `entries[0]`, `entries | last`), those paths read
  directly, and the same through a variable assigned the list; datasource
  and HEEx modules are left alone. Run `mix brando.gen.migrations` for
  `brando_219`, then `mix brando.entries.resave`. The `Brando.Content.Module`
  documentation showed the old path, and now shows `link.vars.header_text`.
