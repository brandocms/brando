defmodule Brando.Villain.Blocks do
  @moduledoc false
  alias Brando.Villain.Blocks

  def list_blocks do
    [
      comment: Blocks.CommentBlock,
      container: Blocks.ContainerBlock,
      # fragment: Blocks.FragmentBlock,
      gallery: Blocks.GalleryBlock,
      header: Blocks.HeaderBlock,
      html: Blocks.HtmlBlock,
      input: Blocks.InputBlock,
      map: Blocks.MapBlock,
      markdown: Blocks.MarkdownBlock,
      media: Blocks.MediaBlock,
      module: Blocks.ModuleBlock,
      picture: Blocks.PictureBlock,
      svg: Blocks.SvgBlock,
      text: Blocks.TextBlock,
      video: Blocks.VideoBlock
    ]
  end
end
