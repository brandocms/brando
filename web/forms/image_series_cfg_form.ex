defmodule Brando.ImageSeriesConfigForm do
  @moduledoc """
  A form for the ImageSeries configuration schema. See the `Brando.Form`
  module for more documentation
  """

  use Brando.Form
  alias Brando.ImageSeries

  form "imageseriesconfig", [schema: ImageSeries,
                             helper: :admin_image_series_path,
                             class: "grid-form"] do
    field :cfg, :textarea
    submit :save, [class: "btn btn-success"]
  end
end
