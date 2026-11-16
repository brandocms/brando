- A content proposal is no longer refused as changed, at apply or at undo, when only a page's breadcrumbs were recomputed, after its parent was retitled or the identity renamed.

- Trashing or restoring a page brings the breadcrumbs of the pages under it up to date at once, instead of on their next save.

- `mix brando.repair.legacy_media` takes the database time zone's UTC offset at the conversion, not at the repair, and the larger one when the clocks changed during the conversion, so a daylight-saving change no longer has it skip every gallery.

- The nightly trash purge no longer fails, and stops purging, when an expired page still has child pages or fragments: they lose the reference and stay, their earlier revisions still restore (a reference in a revision to a row that is gone keeps the entry's current value), an expired row something else still refers to (a user who created a page) is kept for the next run instead of failing the purge every night, and a schema or environment whose purge fails is logged and no longer stops the others.

- A page's parent can no longer be the page itself or a page under it: the save, or the revision restore that would close the loop, is refused with an error on the parent, instead of never returning.
