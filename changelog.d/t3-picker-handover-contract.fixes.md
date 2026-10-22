- **A video added from a URL in a transformer entry's video picker is set on
  the entry** (#3263). The picker hands it over as `video_created_from_url`, which the
  transformer had no clause for: the message was taken as assigns and the
  entry kept its old video. A test now checks that every component opening a
  picker has a clause for each message the picker hands it.
