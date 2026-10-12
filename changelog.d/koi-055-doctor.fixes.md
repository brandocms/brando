- **Content SEO counts a cover image as a sharing image again.** The
  "Sharing image" check expected a path but the audit carries the cover's
  image id, so every entry without a meta image failed it, covers or not, and
  the "Missing image" total counted every audited entry.
