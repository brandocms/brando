- A Bunny video's poster and admin thumbnail no longer break after a custom thumbnail is set in Bunny: they use the name Bunny stores, **Fetch details** picks up a changed one, and `Brando.Release.refresh_bunny_videos()` does that for every Bunny video.
  On a server: `bin/my_app rpc "Brando.Release.refresh_bunny_videos()"`.
