defmodule Brando.Villain.Controller do
  @moduledoc """
  Villain controller actions.

  Defines `:browse_images`, `:upload_image`, `:image_info` actions.

  ## Usage

      use Brando.Villain.Controller,
        image_model: Brando.Image,
        series_model: Brando.ImageSeries

  Add routes to your router.ex:

      villain_routes MyController

  """

  defmacro __using__(options) do
    image_model = Keyword.fetch!(options, :image_model)
    series_model = Keyword.fetch!(options, :series_model)
    quote do
      import Ecto.Query
      @doc false
      def browse_images(conn, %{"slug" => series_slug} = params) do
        series_model = unquote(series_model)

        image_series =
          series_model
          |> preload([:image_category, :images])
          |> Brando.repo.get_by(slug: series_slug)

        if image_series do
          image_list = Enum.map(image_series.images, fn image ->
            sizes =
              Enum.map(image.image.sizes, fn({k, v}) ->
                {k, Brando.Utils.media_url(v)}
              end)
            sizes = Enum.into(sizes, %{})

            %{src: Brando.Utils.media_url(image.image.path),
              thumb: Brando.Utils.media_url(Brando.Utils.img_url(image.image,
                                                                 :thumb)),
              sizes: sizes,
              title: image.image.title, credits: image.image.credits}
          end)
          json(conn, %{status: "200", images: image_list})
        else
          json(conn, %{status: "204", images: []})
        end
      end

      @doc false
      def upload_image(conn, %{"uid" => uid, "slug" => series_slug} = params) do
        series_model = unquote(series_model)
        current_user = Brando.Utils.current_user(conn)

        series =
          series_model
          |> preload(:image_category)
          |> Brando.repo.get_by(slug: series_slug)

        cfg = series.image_category.cfg ||
              Brando.config(Brando.Images)[:default_config]
        opts = Map.put(%{}, "image_series_id", series.id)
        {:ok, image} =
          params
          |> unquote(image_model).check_for_uploads(current_user, cfg, opts)
        sizes =
          Enum.map image.image.sizes, fn({k, v}) ->
            {k, Brando.Utils.media_url(v)}
          end
        sizes = Enum.into(sizes, %{})

        json conn,
          %{status: "200",
            uid: uid,
            image: %{id: image.id,
                     sizes: sizes,
                     src: Brando.Utils.media_url(image.image.path)},
            form: %{
              method: "post",
              action: "villain/imagedata/#{image.id}",
              name: "villain-imagedata",
              fields: [
                %{name: "title",
                  type: "text",
                  label: "Tittel",
                  value: ""},
                %{name: "credits",
                  type: "text",
                  label: "Krediteringer",
                  value: ""}
              ]
            }
          }
      end

      @doc false
      def imageseries(conn, %{"series" => series_slug}) do
        q = from is in unquote(series_model),
                    join: c in assoc(is, :image_category),
                    join: i in assoc(is, :images),
                    where: c.slug == "slideshows" and is.slug == ^series_slug,
                    order_by: i.sequence,
                    preload: [image_category: c, images: i]

        series = Brando.repo.one(q)

        sizes = Enum.map(series.image_category.cfg.sizes, &elem(&1, 0))
        images = Enum.map(series.images, &(&1.image))
        json conn, %{status: 200, series: series_slug, images: images,
                     sizes: sizes, media_url: Brando.config(:media_url)}
      end

      @doc false
      def imageseries(conn, _) do
        q = from is in unquote(series_model),
                    join: c in assoc(is, :image_category),
                    where: c.slug == "slideshows",
                    order_by: is.slug,
                    preload: [image_category: c]
        series =
          q
          |> Brando.repo.all
          |> Enum.map(&(&1.slug))

        json conn, %{status: 200, series: series}
      end

      @doc false
      def image_info(conn, %{"form" => form, "id" => id, "uid" => uid}) do
        form = URI.decode_query(form)
        image_model = unquote(image_model)

        image =
          image_model
          |> Brando.repo.get(id)
        {:ok, image} =
          unquote(image_model).update_image_meta(image, form["title"],
                                                 form["credits"])
        json conn, %{status: 200, id: id, uid: uid,
                     title: image.image.title, credits: image.image.credits,
                     link: form["link"]}
      end
    end
  end
end
