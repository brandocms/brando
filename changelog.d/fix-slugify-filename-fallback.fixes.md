- An upload whose name is only punctuation or emoji before the extension, such as `!!!.jpg`, is stored as `file.jpg` and processed, on server and direct uploads. Slugged filenames also drop punctuation from the extension and are cut to fit a filesystem, so a very long name uploads instead of failing.

- An image whose stored path has no image extension fails processing with a logged error and keeps its sizes, and a bulk size recreate skips it.
