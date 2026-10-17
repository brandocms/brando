# Shared workspaces and form sections

Use `Workspace.header` and the opt-in `admin-workspace` styles for list and
settings screens. Existing generated listing LiveViews also inherit these styles
when `Content.List` is rendered directly inside the main content article. This
compatibility scope includes `Content.header` and its actions, so applications
do not need to regenerate their listings. Explicit workspace wrappers retain
their own layout without a second surrounding workspace. Keep regression
coverage for the old generated markup alongside Pages and the new generator.

Custom listing rows using `update_link` get the title treatment automatically;
they do not require the Pages-specific `listing-title` class. Preserve custom
cells, cover images, checklists, and creator metadata at desktop and mobile sizes.
Keep the original vertical checklist pills and application-defined category
typography. Give metadata columns consistent widths so shorter category lists
share the same left edge as longer ones.
Keep media folder navigation shared between images, files,
and videos. Show the current folder's count using the same scope as the list.
Keep item titles primary; formats, dimensions, file sizes, authors, and timestamps
are secondary information. Avoid exposing URL query strings as video metadata.

Blueprint fieldsets accept `label t("Section name")` for a translated legend.
A read-only `component &Module.preview/1` can render from the current `form`
assigns without maintaining a separate copy of pending values. Keep form IDs,
input names, component IDs, upload targets, and save ownership stable.

Constrain avatar photos and their image wrappers to their container. Source
`width`/`height` attributes and a non-shrinking image wrapper can otherwise expand
a small presence avatar over the page. Clip the photo wrapper, leaving status
dots and focus rings outside it visible. Verify presence after a LiveView patch,
not just on the initial render.
