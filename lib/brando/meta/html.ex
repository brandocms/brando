defmodule Brando.Meta.HTML do
  @moduledoc """
  HTML functions for dealing with meta
  """
  import Brando.Plug.HTML
  import Phoenix.Component

  alias Brando.Cache
  alias Brando.Utils

  @type conn :: Plug.Conn.t()

  @max_meta_description_length 155
  @max_meta_title_length 60

  @doc """
  Renders a <meta> tag
  """
  def meta_tag(%{key: "og:" <> _og_property, value: _value} = assigns) do
    ~H"""
    <meta property={@key} content={@value} />
    """
  end

  def meta_tag(%{key: _key, value: _value} = assigns) do
    ~H"""
    <meta name={@key} content={@value} />
    """
  end

  @doc """
  Renders all meta/opengraph
  """
  @spec render_meta(map) :: any
  def render_meta(%{conn: %{assigns: %{language: language}} = conn} = assigns) do
    app_name = Brando.config(:app_name)
    seo = Brando.Cache.SEO.get(language)

    metas =
      conn
      |> put_meta_if_missing("title", seo.fallback_meta_title)
      |> put_meta_if_missing("og:title", seo.fallback_meta_title)
      |> put_meta_if_missing("og:site_name", app_name)
      |> put_meta_if_missing("og:type", "website")
      |> put_meta_if_missing("og:url", get_canonical(conn) || Utils.current_url(conn))
      |> maybe_put_meta_description(seo.fallback_meta_description)
      |> maybe_put_meta_image(seo.fallback_meta_image)
      |> maybe_add_see_also()
      |> maybe_add_custom_meta()
      |> put_x_card()
      |> get_meta()

    assigns = assign(assigns, :metas, metas)

    ~H"""
    <.meta_tag :for={{key, value} <- @metas} :key={key} key={key} value={value} />
    """
  end

  # we might have malformed or invalid requests without `language` set
  # just return an empty string in that case
  def render_meta(assigns) do
    ~H""
  end

  # X reads its own `twitter:*` tags and falls back to Open Graph for only
  # some of them, so they are written out from the Open Graph values. Tags set
  # by the page or the identity's custom metas win.
  defp put_x_card(conn) do
    image = get_meta(conn, "og:image")

    conn
    |> put_meta_if_missing("twitter:card", if(image, do: "summary_large_image", else: "summary"))
    |> put_present_meta_if_missing("twitter:title", get_meta(conn, "og:title"))
    |> put_present_meta_if_missing("twitter:description", get_meta(conn, "og:description"))
    |> put_present_meta_if_missing("twitter:image", image)
    |> put_present_meta_if_missing("twitter:site", x_handle(conn))
  end

  defp put_present_meta_if_missing(conn, _key, value) when value in [nil, ""], do: conn
  defp put_present_meta_if_missing(conn, key, value), do: put_meta_if_missing(conn, key, value)

  @x_hosts ~w(x.com www.x.com twitter.com www.twitter.com mobile.twitter.com)
  @x_reserved_paths ~w(home i intent search share)

  # The site's handle, from an X profile among the identity's links.
  defp x_handle(%{assigns: %{language: language}}) do
    case Cache.Identity.get(language) do
      %{links: links} when is_list(links) -> Enum.find_value(links, &link_handle/1)
      _ -> nil
    end
  end

  defp link_handle(%{url: url}) when is_binary(url) do
    with %URI{host: host, path: path} when host in @x_hosts and is_binary(path) <- URI.parse(url),
         [handle | _] when handle not in @x_reserved_paths <- String.split(path, "/", trim: true) do
      "@" <> String.trim_leading(handle, "@")
    else
      _ -> nil
    end
  end

  defp link_handle(_link), do: nil

  defp maybe_add_see_also(%{assigns: %{language: language}} = conn) do
    case Cache.Identity.get(language) do
      %{links: []} ->
        conn

      %{links: links} ->
        Enum.reduce(links, conn, fn link, updated_conn ->
          put_meta(updated_conn, "og:see_also", link.url)
        end)

      _ ->
        conn
    end
  end

  defp maybe_add_custom_meta(%{assigns: %{language: language}} = conn) do
    case Cache.Identity.get(language) do
      %{metas: []} ->
        conn

      %{metas: metas} ->
        Enum.reduce(metas, conn, fn meta, updated_conn ->
          put_meta(updated_conn, meta.key, meta.value)
        end)

      _ ->
        conn
    end
  end

  defp maybe_put_meta_description(conn, fallback_meta_description) do
    case get_meta(conn, "description") do
      nil ->
        conn
        |> put_meta("description", fallback_meta_description)
        |> put_meta("og:description", fallback_meta_description)

      _ ->
        conn
    end
  end

  defp maybe_put_meta_image(conn, fallback_meta_image) do
    case get_meta(conn, "og:image") do
      nil ->
        put_meta_image(conn, fallback_meta_image)

      meta_image ->
        put_meta_image(conn, meta_image)
    end
  end

  defp put_meta_image(conn, nil), do: conn

  defp put_meta_image(conn, meta_image) when is_binary(meta_image) do
    img =
      (String.contains?(meta_image, "://") && meta_image) ||
        Utils.hostname(meta_image)

    type =
      meta_image
      |> Path.extname()
      |> String.replace(".", "")
      |> String.downcase()
      |> MIME.type()

    conn
    |> put_meta("image", img, replace: true)
    |> put_meta("og:image", img, replace: true)
    |> put_meta("og:image:type", type, replace: true)
  end

  defp put_meta_image(conn, meta_image) when is_map(meta_image) do
    # grab xlarge from img
    img_src = Utils.img_url(meta_image, :largest, prefix: Utils.media_url())
    img = Utils.hostname(img_src)

    type =
      meta_image.path
      |> Path.extname()
      |> String.replace(".", "")
      |> String.downcase()
      |> MIME.type()

    conn
    |> put_meta("image", img, replace: true)
    |> put_meta("og:image", img, replace: true)
    |> put_meta("og:image:type", type, replace: true)
    |> put_meta("og:image:width", meta_image.width, replace: true)
    |> put_meta("og:image:height", meta_image.height, replace: true)
  end

  @doc """
  Get all `:brando_meta` keys from `conn.private`
  """
  def get_meta(conn) do
    conn.private[:brando_meta] || []
  end

  @doc """
  Get `key` from `:brando_meta` map in `conn.private`.
  """
  def get_meta(conn, key) do
    case List.keyfind(conn.private[:brando_meta], key, 0) do
      {_, value} -> value
      nil -> nil
    end
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
    img_field_size = Keyword.get(opts, :img_field_size, "xlarge")
    title_field = Keyword.get(opts, :title_field, :title)
    description_field = Keyword.get(opts, :description_field, :meta_description)

    meta_image =
      cond do
        Map.get(record, :meta_image) ->
          Enum.join(
            [
              Utils.host_and_media_url(),
              record.meta_image.sizes[img_field_size]
            ],
            "/"
          )

        Map.get(record, img_field) ->
          img = Map.get(record, img_field)

          Enum.join(
            [
              Utils.host_and_media_url(),
              img.sizes[img_field_size]
            ],
            "/"
          )

        true ->
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
