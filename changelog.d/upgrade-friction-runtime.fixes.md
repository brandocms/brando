- **A Blueprint's own `srcset` replaces the default one**. An image or gallery
  config's `srcset` was merged into the site's `default_config.srcset`: a
  legacy flat srcset (`%{"crop_md" => "600w"}`) failed compilation as mixing
  keyed lists with size entries, and a keyed one declaring only `cropped:`
  inherited the default's `default:` list and failed on sizes it does not
  have. A declared `srcset` now replaces the default whole, as `sizes` does.
