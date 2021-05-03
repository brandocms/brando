defmodule BrandoGraphQL.Schema.Types.Video do
  use BrandoWeb, :absinthe

  object :video_type do
    field :url, :string
    field :source, :string
    field :remote_id, :string
    field :width, :integer
    field :height, :integer
    field :thumbnail_url, :string
  end

  input_object :video_type_params do
    field :url, :string
    field :source, :string
    field :remote_id, :string
    field :width, :integer
    field :height, :integer
    field :thumbnail_url, :string
  end
end
