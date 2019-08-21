defmodule Brando.Meta.HTML do
  @moduledoc """
  HTML functions for dealing with meta
  """

  import Phoenix.HTML
  import Phoenix.HTML.Tag
  import Brando.Plug.HTML

  alias Brando.Cache

  @type conn :: Plug.Conn.t()

  @max_meta_description_length 155
  @max_meta_title_length 60

  @doc """
  Renders a <meta> tag
  """
  def meta_tag({"og:" <> og_property, content}),
    do: tag(:meta, content: content, property: "og:" <> og_property)

  def meta_tag({name, content}), do: tag(:meta, content: content, name: name)
  def meta_tag(attrs) when is_list(attrs), do: tag(:meta, attrs)

  def meta_tag("og:" <> og_property, content),
    do: tag(:meta, content: content, property: "og:" <> og_property)

  def meta_tag(name, content), do: tag(:meta, content: content, name: name)

  @doc """
  Renders all meta/opengraph
  """
  @spec render_meta(conn) :: {:safe, term}
  def render_meta(conn) do
    app_name = Brando.config(:app_name)
    title = Brando.Utils.get_page_title(conn)

    conn
    |> put_meta_if_missing("title", "#{title}")
    |> put_meta_if_missing("og:title", "#{title}")
    |> put_meta_if_missing("og:site_name", app_name)
    |> put_meta_if_missing("og:type", "website")
    |> put_meta_if_missing("og:url", Brando.Utils.current_url(conn))
    |> maybe_put_meta_description()
    |> maybe_put_meta_image()
    |> get_meta()
    |> Enum.map(&elem(meta_tag(&1), 1))
    |> raw()
  end

  defp maybe_put_meta_description(conn) do
    case get_meta(conn, "description") do
      nil ->
        if meta_description = Cache.get(:organization, :description) do
          conn
          |> put_meta("description", meta_description)
          |> put_meta("og:description", meta_description)
        else
          conn
        end

      _ ->
        conn
    end
  end

  defp maybe_put_meta_image(conn) do
    case get_meta(conn, "og:image") do
      nil ->
        default_meta_image = Cache.get(:organization, :image)
        put_meta_image(conn, default_meta_image)

      meta_image ->
        put_meta_image(conn, meta_image)
    end
  end

  defp put_meta_image(conn, nil), do: conn

  defp put_meta_image(conn, meta_image) when is_binary(meta_image) do
    img =
      (String.contains?(meta_image, "://") && meta_image) ||
        Brando.Utils.hostname(meta_image)

    type =
      meta_image
      |> Path.extname()
      |> String.replace(".", "")
      |> String.downcase()
      |> MIME.type()

    conn
    |> put_meta("image", img)
    |> put_meta("og:image", img)
    |> put_meta("og:image:type", type)
  end

  defp put_meta_image(conn, meta_image) when is_map(meta_image) do
    require Logger
    Logger.error(inspect(meta_image, pretty: true))
    # grab xlarge from img
    img_src = Brando.Utils.img_url(meta_image, :xlarge, prefix: Brando.Utils.media_url())
    img = Brando.Utils.hostname(img_src)

    type =
      meta_image.path
      |> Path.extname()
      |> String.replace(".", "")
      |> String.downcase()
      |> MIME.type()

    conn
    |> put_meta("image", img)
    |> put_meta("og:image", img)
    |> put_meta("og:image:type", type)
    |> put_meta("og:image:width", meta_image.width)
    |> put_meta("og:image:height", meta_image.height)
  end

  @doc """
  Get all `:brando_meta` keys from `conn.private`
  """
  def get_meta(conn) do
    conn.private[:brando_meta] || %{}
  end

  @doc """
  Get `key` from `:brando_meta` map in `conn.private`.
  """
  def get_meta(conn, key) do
    Map.get(conn.private[:brando_meta], key)
  end

  @doc """
  Try to wrangle some meta data out of `record`

  ### Options

      - `img_field`: The field we try to get the meta image from
      - `img_field_size`: The size key of image field
      - `title_field`: The field we extract the title from
      - `description_field`: The field we extract the description from
  """
  @spec put_record_meta(conn :: Plug.Conn.t(), record :: map, opts :: keyword) :: any
  def put_record_meta(conn, record, opts \\ []) do
    img_field = Keyword.get(opts, :img_field, :cover)
    img_field_size = Keyword.get(opts, :img_field_size, :xlarge)
    title_field = Keyword.get(opts, :title_field, :title)
    description_field = Keyword.get(opts, :description_field, :meta_description)

    meta_image =
      if Map.get(record, img_field, nil) do
        Enum.join(
          [
            Brando.Utils.host_and_media_url(),
            record.cover.sizes[img_field_size]
          ],
          "/"
        )
      else
        nil
      end

    title =
      record
      |> Map.get(title_field, nil)
      |> Brando.HTML.truncate(@max_meta_title_length)

    description =
      record
      |> Map.get(description_field)
      |> Brando.HTML.truncate(@max_meta_description_length)

    conn =
      conn
      |> put_meta("description", description)
      |> put_meta("og:description", description)

    conn =
      if meta_image do
        put_meta(conn, "og:image", meta_image)
      else
        conn
      end

    if title do
      conn
      |> put_meta("title", title)
      |> Brando.Plug.HTML.put_title(title)
    else
      conn
    end
  end
end
