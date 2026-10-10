- **Pasting a YouTube or Vimeo URL in the video picker no longer holds up or
  crashes the editor** (#3129). The picker asked the provider's oEmbed
  endpoint for the title from inside the editor's LiveView, with three
  retries over about seven seconds, so a slow provider froze typing, saving
  and the live preview, and an unreachable one crashed the editor. The
  lookup now runs off the editor, once, with a five-second timeout; when it
  fails, the video is created with the default title. The video goes to the
  field that asked for it, even when the picker is opened for another field
  before the provider answers.
