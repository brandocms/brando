defmodule Brando.Admin.API.Villain.VillainController do
  @moduledoc """
  The API backend for villain-editor JS.
  """
  use Brando.Web, :controller
  alias Brando.Images
  alias Brando.Villain

  @doc false
  def browse_images(conn, %{"slug" => series_slug}) do
    payload =
      case Brando.Images.get_series_by_slug(series_slug) do
        {:ok, image_series} ->
          image_list = Villain.map_images(image_series.images)
          %{status: 200, images: image_list}

        {:error, {:image_series, :not_found}} ->
          %{status: 204, images: []}
      end

    json(conn, payload)
  end

  @doc false
  def upload_image(conn, %{"uid" => uid, "slug" => series_slug} = params) do
    user = Brando.Utils.current_user(conn)

    case Brando.Images.get_series_by_slug(series_slug) do
      {:ok, series} ->
        cfg = series.cfg || Brando.config(Brando.Images)[:default_config]
        params = Map.put(params, "image_series_id", series.id)

        payload =
          case Images.Uploads.Schema.handle_upload(params, cfg, user) do
            {:error, err} ->
              %{
                status: 500,
                error: err
              }

            [{:ok, image}] ->
              sizes = sizes_with_media_url(image)
              sizes_map = Enum.into(sizes, %{})

              %{
                status: 200,
                uid: uid,
                image: %{
                  id: image.id,
                  sizes: sizes_map,
                  src: Brando.Utils.media_url(image.image.path),
                  width: image.image.width,
                  height: image.image.height
                },
                form: %{
                  method: "post",
                  action: "villain/imagedata/#{image.id}",
                  name: "villain-imagedata",
                  fields: [
                    %{
                      name: "title",
                      type: "text",
                      label: "Tittel",
                      value: ""
                    },
                    %{
                      name: "credits",
                      type: "text",
                      label: "Krediteringer",
                      value: ""
                    }
                  ]
                }
              }
          end

        json(conn, payload)

      {:error, {:image_series, :not_found}} ->
        error_msg =
          "Image series `#{series_slug}` not found. Make sure it exists before using it as an upload target"

        json(conn, %{status: 500, error: error_msg})
    end
  end

  @doc false
  def modules(conn, %{"slug" => slug}) do
    {:ok, mods} = Villain.list_modules(%{filter: %{namespace: slug}})
    formatted_mods = Enum.map(mods, fn mod -> %{type: "module", data: mod} end)
    json(conn, formatted_mods)
  end

  defp sizes_with_media_url(image),
    do: Enum.map(image.image.sizes, fn {k, v} -> {k, Brando.Utils.media_url(v)} end)
end
