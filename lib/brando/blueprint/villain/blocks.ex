defmodule Brando.Blueprint.Villain.Blocks do
  alias Brando.Blueprint.Villain.Blocks

  def list_blocks do
    [
      datasource: Blocks.DatasourceBlock,
      gallery: Blocks.GalleryBlock,
      header: Blocks.HeaderBlock,
      module: Blocks.ModuleBlock,
      picture: Blocks.PictureBlock,
      text: Blocks.TextBlock
    ]
  end
end
