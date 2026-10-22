- **The Videos list and a video field show a provider video's frame**. A
  Bunny or Mux video without a thumbnail image of its own showed only the film
  icon there, while the video picker showed its provider's thumbnail; an
  external Bunny stream (`…b-cdn.net/<guid>/playlist.m3u8`) gets its frame
  the same way. `Brando.Videos.Helpers.provider_thumbnail_url/1` is the one
  lookup they share.
