- **Image and video fields in a subform row no longer crash the form** (#3221).
  Picking an image or a video from the picker in a subform row, removing the
  row's image, opening its drawer, or an upload to the row finishing
  processing took the entry form down. The pick is now saved on the row, and
  it stays shown through later edits.

- **The notes drawer ignores a thread id that is not a note id** (#3221). A
  malformed id sent to show, resolve, reopen or reply to a thread crashed the
  entry form.
