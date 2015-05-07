defmodule Villain.Controller do
  @moduledoc """
  Villain controller actions.

  Defines `:upload_image`, `:image_info` actions.

  ## Usage

      use Villain.Controller,
        image_model: Brando.Image,
        series_model: Brando.ImageSeries

  """
  defmacro __using__(options) do
    image_model = Keyword.fetch!(options, :image_model)
    series_model = Keyword.fetch!(options, :series_model)
    quote do
      @doc false
      def browse_images(conn, %{"id" => series_slug} = params) do
        image_series = unquote(series_model).get(slug: series_slug)
        image_list = Enum.map(image_series.images, fn image ->
          %{src: Brando.HTML.media_url(image.image),
            thumb: Brando.HTML.media_url(Brando.Images.Utils.size_dir(image.image, :thumb))}
        end)
        json(conn, %{status: "200", images: image_list})
      end

      @doc false
      def upload_image(conn, %{"uid" => uid, "id" => series_slug} = params) do
        series = unquote(series_model).get(slug: series_slug)
        cfg = series.image_category.cfg || Brando.config(Brando.Images)[:default_config]
        opts = Map.put(%{}, "image_series_id", series.id)
        {:ok, image} = unquote(image_model).check_for_uploads(params, Brando.HTML.current_user(conn), cfg, opts)
        json conn,
          %{status: "200",
            uid: uid,
            image: %{id: image.id, src: Brando.HTML.media_url(image.image.path)},
            form: %{
              method: "post",
              action: "villain/bildedata/#{image.id}",
              name: "villain-imagedata",
              fields: [
                %{name: "title",
                  type: "text",
                  label: "Tittel",
                  value: ""},
                %{name: "credits",
                  type: "text",
                  label: "Krediteringer",
                  value: ""
                }
              ]
            }
          }
      end

      @doc false
      def image_info(conn, %{"form" => form, "id" => id, "uid" => uid}) do
        form = URI.decode_query(form)
        {:ok, image} = unquote(image_model).update_image_meta(unquote(image_model).get(id: id), form["title"], form["credits"])
        json conn, %{status: 200, id: id, uid: uid,
                     title: image.image.title, credits: image.image.credits}
      end
    end
  end
end