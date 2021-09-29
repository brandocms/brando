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
      map: Blocks.MapBlock,
      markdown: Blocks.MarkdownBlock,
      media: Blocks.MediaBlock,
      module: Blocks.ModuleBlock,
      picture: Blocks.PictureBlock,
      svg: Blocks.SvgBlock,
      table: Blocks.TableBlock,
      text: Blocks.TextBlock,
      video: Blocks.VideoBlock
    ]
  end
end
