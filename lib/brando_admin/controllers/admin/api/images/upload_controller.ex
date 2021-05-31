defmodule BrandoAdmin.API.Images.UploadController do
  @moduledoc """
  Uploads, breh!
  """

  use BrandoAdmin, :controller
  use Brando.Sequence.Controller, schema: Brando.Image
  alias Brando.Images

  @doc false
  def post(conn, %{"image_series_id" => id} = params) do
    user = Guardian.Plug.current_resource(conn)

    cfg =
      case Images.get_series_config(id) do
        {:error, _} -> Brando.config(Brando.Images)[:default_config]
        {:ok, cfg} -> cfg
      end

    case Images.Uploads.Schema.handle_upload(params, cfg, user) do
      {:error, error_msg} ->
        conn
        |> put_status(400)
        |> render(:post, status: 400, error_msg: error_msg)

      images when length(images) > 1 ->
        images = Enum.map(images, fn {:ok, img} -> img end)
        render(conn, :post, images: images, status: 200, error_msg: nil)

      [{:ok, image}] ->
        render(conn, :post, image: image, status: 200, error_msg: nil)
    end
  end
end
