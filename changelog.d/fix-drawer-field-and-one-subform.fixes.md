- **A restored image, video or file drawer only opens for a media field** (#3223).
  After a reconnect, the entry form reopens the drawer the editor had open,
  from what the page tells it. A drawer named for a field that is not an
  image, video or file field of that kind in the form (a date, for example)
  used to open, and picking an asset in it then crashed the form. Such a
  drawer now stays closed, and a pick for a field without a media relation
  is ignored.

- **An image uploaded to a one-to-one subform shows on that subform when it
  finishes processing** (#3223). When processing finished, the image was put
  on the entry in place of the whole subform (an article's `author` became
  the image), instead of on the subform's image field.
