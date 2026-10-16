- **Image and video fields in a subform row no longer crash the form**.
  Picking an image or a video from the picker in a subform row, removing the
  row's image, or an upload to the row finishing processing took the entry
  form down; each is now saved on the row.

- **The notes drawer ignores a thread id that is not a number**. A
  malformed id sent to show, resolve, reopen or reply to a thread crashed the
  entry form.
