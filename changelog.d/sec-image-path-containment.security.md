- An editor can no longer make the crop editor write files outside the media root: the image form ignores a non-superuser's path, configuration target, dimensions and sizes, and the crop editor, image deletion and the other file operations on a stored image or file path refuse a path that leaves the media root.

- `readonly: :unless_superuser`, `disabled: :unless_superuser` and `superuser` fieldsets are now enforced when the form saves, not only in the browser, and a new `media_path: true` attribute constraint validates stored media paths.
