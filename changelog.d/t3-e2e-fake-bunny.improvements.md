- **Bunny's tus endpoint can be configured** with `tus_endpoint` under
  `config :brando, Brando.Videos.Uploaders.Bunny`. It defaults to Bunny's own
  `https://video.bunnycdn.com/tusupload`; a path is resolved against the admin
  page, so uploads can go to a test double on the site itself.
