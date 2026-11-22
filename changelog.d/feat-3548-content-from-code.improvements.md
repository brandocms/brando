- Generated `delete_*` functions and `Brando.Pages.delete_page/3` take the entry as well as its id; an entry loaded in another environment raises `ArgumentError` instead of deleting the entry with its id here.

- `Brando.Test.build_block/2` and `render_block/2` give a media ref the type of the image, video or gallery they are given, so it renders, and take file paths and lists for galleries as `Brando.Content.Seed.block/3` does.
