- A focal point saved with `Brando.Images.update_image/3` renders the entries that show the image again, as a save from the image editor or drawer does.

- The image editor's Save changes the image, never a field locked for the editor: a locked field keeps its image and the form is not validated with another.

- Uploading or picking an image in a one-to-one subform with no row yet (an article's author) starts the row instead of crashing the form.
