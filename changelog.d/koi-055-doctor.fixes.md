- **Content SEO counts a cover image as a sharing image again.** The
  "Sharing image" check expected a path but the audit carries the cover's
  image id, so every entry without a meta image failed it, covers or not, and
  the "Missing image" total counted every audited entry.

- **`mix brando.images.adopt`, the doctor and Utilities no longer recommend
  recreating every image on a copy without the media.** When none of the
  images has a file in the media folder (empty, not mounted, or never synced
  to this machine), `mix brando.images.adopt` stops with
  `No image files found under <media path>`, the doctor's Image configs check
  asks for the media instead of a recreate, and Utilities → Image sizes says
  the same and no longer highlights **Recreate changed images**. A single
  missing file is now named (`large: file missing: images/site/default/large/x.jpg`)
  where it read `large is missing`, which looked like a missing size key. The
  doctor also counts how the images that differ differ (in formats, sizes,
  missing files or dimensions), so a real config change, such as a default
  config that gained `:webp`, stands apart from files missing on this machine.
