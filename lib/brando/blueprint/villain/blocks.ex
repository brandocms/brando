defmodule Brando.Blueprint.Villain.Blocks do
  alias Brando.Blueprint.Villain.Blocks

  def list_blocks do
    [
      container: Blocks.ContainerBlock,
      datasource: Blocks.DatasourceBlock,
      gallery: Blocks.GalleryBlock,
      header: Blocks.HeaderBlock,
      html: Blocks.HtmlBlock,
      module: Blocks.ModuleBlock,
      picture: Blocks.PictureBlock,
      text: Blocks.TextBlock
    ]
  end
end
