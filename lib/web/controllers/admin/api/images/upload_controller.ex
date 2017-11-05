defmodule Brando.Admin.API.Images.UploadController do
  @moduledoc """
  Uploads, breh!
  """

  use Brando.Web, :controller
  use Guardian.Phoenix.Controller

  use Brando.Sequence, [
    :controller, [
      schema:  Brando.Image,
      filter: &Brando.Image.for_series_id/1
    ]
  ]

  import Ecto.Query

  alias Brando.ImageSeries
  alias Brando.Images

  @doc false
  def post(conn, %{"image_series_id" => id} = params, current_user, _) do
    {:ok, series} =
      id
      |> Images.get_series()
      |> Images.preload_series()

    opts = Map.put(%{}, "image_series_id", series.id)
    cfg  = series.cfg || Brando.config(Brando.Images)[:default_config]

    case Images.check_for_uploads(params, current_user, cfg, opts) do
      {:ok, image} ->
        render conn, :post, image: image, status: 200, error_msg: nil
      {:error, error_msg} ->
        conn
        |> put_status(400)
        |> render(:post, status: 400, error_msg: error_msg)
    end
  end
end
