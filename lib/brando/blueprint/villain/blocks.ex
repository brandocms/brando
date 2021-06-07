defmodule Brando.Blueprint.Villain.Blocks do
  alias Brando.Blueprint.Villain.Blocks

  def list_blocks do
    [
      module: Blocks.ModuleBlock,
      picture: Blocks.PictureBlock,
      gallery: Blocks.GalleryBlock,
      header: Blocks.HeaderBlock,
      text: Blocks.TextBlock
    ]
  end
end
