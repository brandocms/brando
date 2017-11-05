defmodule Brando.VillainController do
  use Brando.Web, :controller
  import Ecto.Query

  @doc false
  def browse_images(conn, %{"slug" => series_slug} = params) do
    image_series =
      Brando.ImageSeries
      |> preload([:image_category, :images])
      |> Brando.repo.get_by(slug: series_slug)

    if image_series do
      image_list = Brando.Villain.map_images(image_series.images)
      json(conn, %{status: 200, images: image_list})
    else
      json(conn, %{status: 204, images: []})
    end
  end

  @doc false
  def upload_image(conn, %{"uid" => uid, "slug" => series_slug} = params) do
    user = Brando.Utils.current_user(conn)

    series =
      Brando.ImageSeries
      |> preload(:image_category)
      |> Brando.repo.get_by(slug: series_slug)

    if series == nil do
      raise Brando.Exception.UploadError,
            "villain could not find image series `#{series_slug}`. \n\n" <>
            "Make sure it exists before using it as an upload target!\n"
    end

    cfg  = series.cfg || Brando.config(Brando.Images)[:default_config]
    opts = Map.put(%{}, "image_series_id", series.id)

    {:ok, image} = Brando.Images.check_for_uploads(params, user, cfg, opts)

    sizes     = Enum.map(image.image.sizes, fn({k, v}) -> {k, Brando.Utils.media_url(v)} end)
    sizes_map = Enum.into(sizes, %{})

    json conn,
      %{
        status: 200,
        uid:    uid,
        image: %{
          id:    image.id,
          sizes: sizes_map,
          src:   Brando.Utils.media_url(image.image.path)
        },
        form: %{
          method: "post",
          action: "villain/imagedata/#{image.id}",
          name:   "villain-imagedata",
          fields: [
            %{
              name:  "title",
              type:  "text",
              label: "Tittel",
              value: ""
            },
            %{
              name:  "credits",
              type:  "text",
              label: "Krediteringer",
              value: ""
            }
          ]
        }
      }
  end

  @doc false
  def imageseries(conn, %{"series" => series_slug}) do
    series = (
      from is in Brando.ImageSeries,
            join: c in assoc(is, :image_category),
            join: i in assoc(is, :images),
           where: c.slug == "slideshows" and is.slug == ^series_slug,
        order_by: i.sequence,
         preload: [image_category: c, images: i]
    )
    |> first
    |> Brando.repo.one!

    sizes  = Enum.map(series.cfg.sizes, &elem(&1, 0))
    images = Enum.map(series.images, &(&1.image))

    json conn, %{
      status:    200,
      series:    series_slug,
      images:    images,
      sizes:     sizes,
      media_url: Brando.config(:media_url)
    }
  end

  @doc false
  def imageseries(conn, _) do
    series = Brando.repo.all(
      from is in Brando.ImageSeries,
            join: c in assoc(is, :image_category),
           where: c.slug == "slideshows",
        order_by: is.slug,
         preload: [image_category: c]
    )

    series_slugs = Enum.map(series, &(&1.slug))
    json conn, %{status: 200, series: series_slugs}
  end

  @doc false
  def image_info(conn, %{"form" => form, "id" => id, "uid" => uid}) do
    form         = URI.decode_query(form)
    image        = Brando.repo.get(Brando.Image, id)

    {:ok, image} =
      Brando.Images.update_image_meta(image, form["title"], form["credits"])

    info = %{
      status:  200,
      id:      id,
      uid:     uid,
      title:   image.image.title,
      credits: image.image.credits,
      link:    form["link"]
    }

    json conn, info
  end
end
