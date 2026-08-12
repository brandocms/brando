# Villain parser

The parser turns block data into HTML. `mix brando.install` generates one for
your project:

```elixir
# lib/my_app_web/villain/parser.ex
defmodule MyApp.Villain.Parser do
  use Brando.Villain.Parser
end
```

and points Brando at it:

```elixir
# config/brando.exs
config :brando, Brando.Villain, parser: MyApp.Villain.Parser
```

`use Brando.Villain.Parser` defines every callback for you, delegating to
Brando's default implementation, and marks each one `defoverridable`. An empty
parser module is therefore a complete one — you override only what you want to
render differently.

See the [Block editor](block_editor.md) guide for how modules, refs and vars fit
together; this guide is about the rendering step at the end of that pipeline.

## When it runs

Blocks are rendered to HTML at **save time** and the result is stored on the
entry, so the parser is not in the request path for normal page rendering:

```elixir
Brando.Villain.parse(entry.entry_blocks, entry)
```

walks the entry's root blocks and calls `parser.<block type>(block, opts)` for
each. Modules and containers recurse into their children, and `{% ref refs.name %}`
in a module template calls the ref's block type.

Because output is persisted, **changing your parser does not change existing
entries** until they are re-rendered. `mix brando.entries.resave` re-renders
everything.

## Callbacks

Every callback takes `(data, opts)` and returns iodata, except the two helpers
at the bottom.

**Block types reachable from a module ref** (`{% ref refs.name %}`):

| Callback | Notes |
|---|---|
| `header/2` | |
| `text/2` | |
| `html/2` | |
| `svg/2` | |
| `markdown/2` | |
| `picture/2` | see *What the media callbacks receive* |
| `video/2` | " |
| `gallery/2` | " |
| `file/2` | " |
| `map/2` | |
| `comment/2` | renders `""` — comments are editor-only notes |
| `media/2` | a media block where the editor picked no type; renders `""` |
| `fragment/2` | embeds another entry's rendered blocks |
| `input/2` | deprecated |

**Structural**, called by `Brando.Villain.parse/3` and by each other:

| Callback | Notes |
|---|---|
| `module/2` | renders a module, its vars and refs; handles multi-modules |
| `container/2` | renders a palette-aware `<section>` and recurses into children |

**Helpers**, called by other callbacks rather than dispatched to by block type:

| Callback | Notes |
|---|---|
| `render_caption/1` | builds the caption string from `title` and `credits`; used by `picture/2` and `gallery/2` |
| `video_file_options/1` | the options list passed to `<.video>` for file-backed videos |

**Deprecated**, kept for old content — they have no block module, so nothing in
the editor can produce them: `blockquote/2`, `datatable/2`, `divider/2`,
`list/2`, `table/2`, `timeline/2`, `datasource/2`.

### What the media callbacks receive

The media callbacks do **not** get the raw block data. Before dispatch, the
ref's associated media record is loaded and the block's own settings are merged
onto it, so the callback gets one struct carrying everything:

| Callback | `data` is |
|---|---|
| `picture/2` | `%Brando.Images.Image{}`, with the block's presentation settings (`lazyload`, `placeholder`, `moonwalk`, `picture_class`, `img_class`, `link`, `srcset`) merged onto it as virtual fields. Falls back to `%PictureBlock.Data{}` when the ref has no image. |
| `video/2` | `%Brando.Videos.Video{}`, with the block's overrides merged the same way (`poster`, `opacity`, `play_button`, `progress`, `cover`, `cover_image`, plus the playback columns). Falls back to `%VideoBlock.Data{}`. |
| `gallery/2` | `%GalleryBlock.Data{}` with the resolved `%Brando.Galleries.Gallery{}` on its virtual `gallery` field. Read `data.gallery.gallery_objects` — each holds an `image` **or** a `video`, already carrying any per-object caption and playback overrides. |
| `file/2` | a plain map of the block's fields plus `:file`, `:filename`, `:filesize` and `:mime_type`. |

Every other callback receives its block's own `Data` struct.

### opts

| Key | |
|---|---|
| `:parser_module` | the configured parser — see *Calling one callback from another* |
| `:modules`, `:containers`, `:palettes`, `:fragments` | preloaded render sources, only what this block type needs |
| `:context` | the Liquex context (entry, identity, globals, navigation, language, …) |
| `:skip_children` | `true` renders a `[$ content $]` placeholder instead of children; `:force_render` renders children of an inactive container |
| `:annotate_blocks` | wraps output in `<!-- [+:B<uid>] -->` comments, for live preview diffing |
| `:format_html` | runs the result through the HEEx formatter |

## Overriding

Define the callback in your parser module. A common case is changing the options
a video block passes to the player:

```elixir
defmodule MyApp.Villain.Parser do
  use Brando.Villain.Parser

  def video_file_options(data) do
    [
      width: Map.get(data, :width),
      height: Map.get(data, :height),
      autoplay: Map.get(data, :autoplay, false),
      preload: true,
      controls: Map.get(data, :controls, false),
      # this design never wants the generated SVG cover
      cover: false,
      # ...but does want a progress bar whenever there's a play button
      progress: Map.get(data, :play_button, false),
      play_button: Map.get(data, :play_button, false)
    ]
  end
end
```

To build on the default rather than replace it, call it explicitly:

```elixir
def text(data, opts) do
  ["<div class=\"prose\">", Brando.Villain.Parser.text(data, opts), "</div>"]
end
```

### Calling one callback from another

If your override needs another callback, dispatch through the configured parser
so that your other overrides apply:

```elixir
def picture(data, opts) do
  caption = Brando.Villain.Parser.parser_module(opts).render_caption(data)
  # ...
end
```

Calling `Brando.Villain.Parser.render_caption/1` directly gets you Brando's
implementation, not yours — silently. This is the rule Brando's own
implementations follow internally, and it is what
`test/brando/villain/parser/dispatch_test.exs` guards.

## Galleries

`gallery/2` is the callback most projects end up overriding, because gallery
markup is design-specific. The default renders `gallery.gallery_objects` in
sequence — images through the picture component, videos through the video
component — inside one of three wrappers chosen by `data.type`:

| `type` | wrapper |
|---|---|
| `:gallery` | `<div data-gallery>` → `<section data-gallery-items>` |
| `:slider` | `<div data-panner-container>` → `<section data-panner>`, items as `<figure data-panner-item>` |
| `:slideshow` | `<div data-slideshow>` |

A gallery object holds either an image or a video, so an override has to handle
both:

```elixir
def gallery(%{gallery: %Brando.Galleries.Gallery{gallery_objects: objects}} = data, opts) do
  items =
    Enum.map(objects, fn
      %{image: %Brando.Images.Image{} = image} -> render_my_image(image, data)
      %{video: %Brando.Videos.Video{} = video} -> render_my_video(video, opts)
      _ -> ""
    end)

  ["<div class=\"my-gallery\">", items, "</div>"]
end
```
