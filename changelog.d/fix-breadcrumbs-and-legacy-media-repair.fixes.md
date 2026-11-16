- A content proposal is no longer refused as changed, at apply or at undo, when only a page's breadcrumbs were recomputed, after its parent was retitled or the identity renamed.

- Trashing or restoring a page brings the breadcrumbs of the pages under it up to date at once, instead of on their next save.

- `mix brando.repair.legacy_media` takes the database time zone's UTC offset at the conversion, not at the repair, so a daylight-saving change in between no longer has it skip every gallery.
