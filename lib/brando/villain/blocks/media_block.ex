defmodule Brando.Villain.Blocks.MediaBlock do
  @moduledoc false
  use Brando.Villain.Block,
    type: "media"

  defmodule Data do
    @moduledoc false
    use Brando.Blueprint,
      application: "Brando",
      domain: "Villain",
      schema: "MediaBlockData",
      singular: "media_block_data",
      plural: "media_block_datas",
      gettext_module: Brando.Gettext

    alias Brando.Villain.Blocks

    @primary_key false
    data_layer :embedded
    identifier false
    persist_identifier false

    attributes do
      attribute :available_blocks, {:array, :string}, default: ["picture", "video"]
    end

    relations do
      relation :template_picture, :embeds_one, module: Blocks.PictureBlock.Data, on_replace: :delete
      relation :template_video, :embeds_one, module: Blocks.VideoBlock.Data, on_replace: :delete
      relation :template_gallery, :embeds_one, module: Blocks.GalleryBlock.Data, on_replace: :delete
      relation :template_svg, :embeds_one, module: Blocks.SvgBlock.Data, on_replace: :delete
      relation :template_file, :embeds_one, module: Blocks.FileBlock.Data, on_replace: :delete
    end
  end

  alias Brando.Villain.Blocks

  @doc """
  The block a media ref holds once `type` is chosen for it: a block of that
  type with the ref's template for it (`template_picture` and so on). With
  no template its data is nil, except a file's, which is its empty data.
  `data` is the media ref's `Data`, or nil.
  """
  def typed(data, "picture"), do: %Blocks.PictureBlock{type: "picture", data: template(data, :template_picture)}
  def typed(data, "video"), do: %Blocks.VideoBlock{type: "video", data: template(data, :template_video)}
  def typed(data, "gallery"), do: %Blocks.GalleryBlock{type: "gallery", data: template(data, :template_gallery)}
  def typed(data, "svg"), do: %Blocks.SvgBlock{type: "svg", data: template(data, :template_svg)}
  def typed(data, "file"), do: %Blocks.FileBlock{type: "file", data: file_template(data)}

  @doc """
  The types a media ref with `data` lets an editor choose.
  """
  def available_blocks(%{available_blocks: types}) when is_list(types), do: types
  def available_blocks(_data), do: ["picture", "video"]

  defp template(data, key), do: data && Map.get(data, key)

  defp file_template(data), do: template(data, :template_file) || %Blocks.FileBlock.Data{}
end
