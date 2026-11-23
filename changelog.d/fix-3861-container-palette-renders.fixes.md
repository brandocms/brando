- Deleting a container renders again the entries whose blocks use it: their content shows in a plain section with the block's palette, and restoring the container from the trash renders it in the container again.

- Saving a palette clears the cached containers that hold it, so a render right after reads the saved palette.

- A section whose palette is in the trash renders as a plain section, without its colours, instead of failing its render and keeping its old HTML.
