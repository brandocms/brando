- The Figma image import sets a cropped image's focal point so the site shows the crop Figma
  shows, not the centre of the crop, which showed another part of the photo when the crop was
  not centred ([#3730](https://github.com/brandocms/brando/issues/3730)). The focal point now
  has a mode: `:center` (the default, how every existing image is cut) or `:position`, which the
  import sets, so the sizes Brando cuts and the share cards follow the Figma crop too. Moving
  the focal point by hand sets the mode back to `:center`. Images imported before keep their
  focal point.
