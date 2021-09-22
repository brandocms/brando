defmodule Brando.Blueprint.Villain.Blocks do
  alias Brando.Blueprint.Villain.Blocks

  def list_blocks do
    [
      comment: Blocks.CommentBlock,
      container: Blocks.ContainerBlock,
      datasource: Blocks.DatasourceBlock,
      gallery: Blocks.GalleryBlock,
      header: Blocks.HeaderBlock,
      html: Blocks.HtmlBlock,
      markdown: Blocks.MarkdownBlock,
      module: Blocks.ModuleBlock,
      picture: Blocks.PictureBlock,
      svg: Blocks.SvgBlock,
      text: Blocks.TextBlock,
      video: Blocks.VideoBlock
    ]
  end
end
