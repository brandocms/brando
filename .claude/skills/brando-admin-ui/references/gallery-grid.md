# Gallery grid (contact sheet)

The gallery field and the gallery block share one grid view, approved as design
3a on 4 October 2026. Square thumbnails
(`object-fit: cover`) join into one block: an outer `--brando-line` border with a 6px
radius, hairlines drawn as each cell's 1px outline over a 1px gap on a white
grid, so the empty cells of a short last row stay white. Five columns, six once
the sheet is wider than about 905px (a grid formula; EuropaCSS reserves
`@container`). Each square carries its position (a white 20px chip, top left), a
"▶ Video" badge, and on hover the edit-image, configure and remove actions (top
right) with a 2px `--brando-line-strong` outline. Bottom left sit the caption icon (images and
videos) and the ALT chip (images only): white when set, faded for an empty caption
— captions are optional — and amber (`--brando-attention`/`--brando-attention-ink`) for missing alt text.
Hovering an icon shows its text in a dark peek; clicking it opens a popover under
the square, flipped to the right edge near the sheet's end, with "Caption ·
filename" or "Alt text · filename", the input, "Saved for this gallery only. Empty
uses the image library's text." and Cancel/Save. A legend under the grid keys the
icons and counts images with no alt text. Captions are rich text (bold, italic,
link) everywhere they are edited; alt text stays plain. The popover writes exactly
what the object's configuration dialog writes, so the two stay in step.

`Gallery.Tile` owns the square, popover, legend and view switch; `Gallery.css`
owns their styles. The grid/list switch — two 28×26 icon buttons at the right end
of the gallery toolbar, the selected one `--brando-surface-selected` with `--brando-accent` ink — is the
admin's view only. It starts at the field's `layout:` or the block's `display`,
is remembered per field or block in `localStorage` (`Brando.GalleryView`), and
never changes saved content.
