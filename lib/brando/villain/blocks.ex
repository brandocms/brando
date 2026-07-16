defmodule Brando.Villain.Blocks do
  @moduledoc false

  @blocks [
    comment: Module.concat(["Brando", "Villain", "Blocks", "CommentBlock"]),
    container: Module.concat(["Brando", "Villain", "Blocks", "ContainerBlock"]),
    file: Module.concat(["Brando", "Villain", "Blocks", "FileBlock"]),
    gallery: Module.concat(["Brando", "Villain", "Blocks", "GalleryBlock"]),
    header: Module.concat(["Brando", "Villain", "Blocks", "HeaderBlock"]),
    html: Module.concat(["Brando", "Villain", "Blocks", "HtmlBlock"]),
    input: Module.concat(["Brando", "Villain", "Blocks", "InputBlock"]),
    map: Module.concat(["Brando", "Villain", "Blocks", "MapBlock"]),
    markdown: Module.concat(["Brando", "Villain", "Blocks", "MarkdownBlock"]),
    media: Module.concat(["Brando", "Villain", "Blocks", "MediaBlock"]),
    module: Module.concat(["Brando", "Villain", "Blocks", "ModuleBlock"]),
    picture: Module.concat(["Brando", "Villain", "Blocks", "PictureBlock"]),
    svg: Module.concat(["Brando", "Villain", "Blocks", "SvgBlock"]),
    text: Module.concat(["Brando", "Villain", "Blocks", "TextBlock"]),
    video: Module.concat(["Brando", "Villain", "Blocks", "VideoBlock"])
  ]

  @spec list_blocks() :: keyword(module())
  def list_blocks, do: @blocks
end
