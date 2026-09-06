defmodule Brando.Villain.Blocks do
  @moduledoc false

  @blocks [
    blocks: Module.concat(["Brando", "Villain", "Blocks", "BlocksBlock"]),
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

  # A `media` ref in a module is a slot, not a fixed type: `MediaBlock.Data`
  # carries a template for each of these, and each of them defines a
  # `MediaBlock`-specific `apply_ref/3` clause that reads its own template out of
  # the source. So a block ref of any of these types is still driven by a `media`
  # module ref — it has not been retyped out from under the editor.
  @media_slot_blocks [:picture, :video, :gallery, :svg]

  @spec list_blocks() :: keyword(module())
  def list_blocks, do: @blocks

  @doc """
  True when a module ref of type `module_type` can still drive a block ref of
  type `block_type`.

  Identical types always can. Beyond that, only the `media` slot: it exists
  precisely so one module ref can back a picture, video, gallery or svg,
  depending on what the editor put there.
  """
  @spec ref_types_compatible?(module() | nil, module() | nil) :: boolean()
  def ref_types_compatible?(nil, _block_type), do: false
  def ref_types_compatible?(_module_type, nil), do: false
  def ref_types_compatible?(same, same), do: true

  def ref_types_compatible?(module_type, block_type) do
    media = Keyword.fetch!(@blocks, :media)
    module_type == media and block_type in Enum.map(@media_slot_blocks, &Keyword.fetch!(@blocks, &1))
  end
end
