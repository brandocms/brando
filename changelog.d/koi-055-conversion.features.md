- **`mix brando.repair.legacy_media` puts back the media an older
  `brando_133` lost.** For sites converted before `brando_133` made images of
  legacy media without a row: it takes the media findings of
  `mix brando.check.legacy_conversion` and, from the Villain columns the site
  still has, links each picture to the live image its legacy `sizes` or
  `path` name or makes the row from the legacy data, adds a gallery's missing
  images at their legacy places, and links a video ref to its video. It
  writes only where it can tell the media was lost in the conversion rather
  than removed by an editor since, and skips the rest with the reason: an
  entry whose blocks no longer line up with Villain's at any level (a block
  added, removed or replaced) or whose ref is of another type now; an entry,
  block or gallery edited since the conversion (`edited_at` against when
  brando_133 and brando_175 ran, or `--converted-at`); and, once the
  conversion is more than 30 days old, any image or video it would have to
  make, since emptying the trash leaves no trace of what an editor deleted.
  It locks each ref and writes only while the ref is still empty.
  `--dry-run` lists what it would do and writes nothing; a second run finds
  nothing to do. With the Villain columns dropped it says so and stops. Run
  `mix brando.entries.resave` afterwards.

- **`mix brando.doctor` lists module code that reads entries through
  `.data.vars`.** The Module entry paths check finds Liquid module code (not
  datasource modules) that still reads `.data.vars` or `.data.refs`, which
  renders nothing since the blocks conversion, with module and line:
  whatever `brando_219` could not rewrite, and code written the old way
  since.
