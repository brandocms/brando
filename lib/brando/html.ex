defmodule Brando.HTML do
  @moduledoc """
  Helper and convenience functions.
  """

  @type alert_levels :: :default | :primary | :info | :success | :warning | :danger
  @type conn :: Plug.Conn.t()

  import Brando.Utils, only: [current_user: 1, active_path?: 2]
  import Brando.Meta.Controller, only: [put_meta: 3, get_meta: 1, get_meta: 2]
  import Phoenix.HTML
  import Phoenix.HTML.Tag

  @doc false
  defmacro __using__(_) do
    quote do
      import Brando.HTML
    end
  end

  @doc """
  Returns `active` if `conn`'s `full_path` matches `current_path`.
  """
  @spec active(conn, String.t()) :: String.t()
  def active(conn, url_to_match, add_class? \\ nil) do
    result = (add_class? && ~s(class="active")) || "active"
    (active_path?(conn, url_to_match) && result) || ""
  end

  @doc """
  Checks if current_user in conn has `role`
  """
  @spec can_render?(conn, map) :: boolean
  def can_render?(_, %{role: nil}) do
    true
  end

  def can_render?(conn, %{role: role}) do
    current_user = current_user(conn)

    if current_user do
      (role in current_user(conn).role && true) || false
    else
      false
    end
  end

  def can_render?(_, _), do: true

  @doc """
  Zero pad `val` as a binary.

  ## Example

      iex> zero_pad(5)
      "005"

  """
  @spec zero_pad(val :: String.t() | Integer.t(), count :: Integer.t()) :: String.t()
  def zero_pad(str, count \\ 3)
  def zero_pad(val, count) when is_binary(val), do: String.pad_leading(val, count, "0")

  def zero_pad(val, count) when is_integer(val),
    do: String.pad_leading(Integer.to_string(val), count, "0")

  @doc """
  Split `full_name` and return first name
  """
  def first_name(full_name) do
    full_name
    |> String.split()
    |> hd
  end

  @doc """
  Returns a red X if value is nil, or a check if the value is truthy
  """
  @spec check_or_x(val :: nil | bool) :: String.t()
  def check_or_x(nil), do: ~s(<i class="icon-centered fa fa-times text-danger"></i>)
  def check_or_x(false), do: ~s(<i class="icon-centered fa fa-times text-danger"></i>)
  def check_or_x(_), do: ~s(<i class="icon-centered fa fa-check text-success"></i>)

  @doc """
  Displays a banner informing about cookie laws
  """
  def cookie_law(conn, text, opts \\ []) do
    if Map.get(conn.cookies, "cookielaw_accepted") != "1" do
      text = raw(text)
      button_text = Keyword.get(opts, :button_text, "OK")
      info_link = Keyword.get(opts, :info_link, "/cookies")
      info_text = Keyword.get(opts, :info_text)

      content_tag :div, class: "container cookie-container" do
        content_tag :div, class: "cookie-container-inner" do
          content_tag :div, class: "cookie-law" do
            [
              content_tag :div, class: "cookie-law-text" do
                content_tag(:p, text)
              end,
              content_tag :div, class: "cookie-law-buttons" do
                [
                  content_tag(:button, button_text, class: "dismiss-cookielaw"),
                  if info_text do
                    content_tag :a, href: info_link, class: "info-cookielaw" do
                      info_text
                    end
                  else
                    []
                  end
                ]
              end
            ]
          end
        end
      end
    end
  end

  @doc """
  Output Google Analytics code for `code`

  ## Example

      google_analytics("UA-XXXXX-X")

  """
  @spec google_analytics(ua_code :: String.t()) :: {:safe, term}
  def google_analytics(ua_code) do
    content =
      """
      (function(b,o,i,l,e,r){b.GoogleAnalyticsObject=l;b[l]||(b[l]=
      function(){(b[l].q=b[l].q||[]).push(arguments)});b[l].l=+new Date;
      e=o.createElement(i);r=o.getElementsByTagName(i)[0];
      e.src='//www.google-analytics.com/analytics.js';
      r.parentNode.insertBefore(e,r)}(window,document,'script','ga'));
      ga('create','#{ua_code}','auto');ga('set', 'anonymizeIp', true);ga('send','pageview');
      """
      |> raw

    content_tag(:script, content)
  end

  @doc """
  Truncate `text` to `length`
  """
  def truncate(nil, _), do: ""

  def truncate(text, len) when is_binary(text),
    do: (String.length(text) <= len && text) || String.slice(text, 0..len) <> "..."

  def truncate(val, _), do: val

  @doc """
  Renders a <meta> tag
  """
  def meta_tag({"og:" <> og_property, content}) do
    tag(:meta, content: content, property: "og:" <> og_property)
  end

  def meta_tag({name, content}) do
    tag(:meta, content: content, name: name)
  end

  def meta_tag(attrs) when is_list(attrs) do
    tag(:meta, attrs)
  end

  def meta_tag("og:" <> og_property, content) do
    tag(:meta, content: content, property: "og:" <> og_property)
  end

  def meta_tag(name, content) do
    tag(:meta, content: content, name: name)
  end

  @doc """
  Renders all meta/opengraph
  """
  @spec render_meta(conn) :: {:safe, term}
  def render_meta(conn) do
    app_name = Brando.config(:app_name)
    title = Brando.Utils.get_page_title(conn)

    conn
    |> put_meta("title", "#{title}")
    |> put_meta("og:title", "#{title}")
    |> put_meta("og:site_name", app_name)
    |> put_meta("og:type", "website")
    |> put_meta("og:url", Brando.Utils.current_url(conn))
    |> maybe_put_meta_keywords()
    |> maybe_put_meta_description()
    |> maybe_put_meta_image
    |> get_meta()
    |> Enum.map(&elem(meta_tag(&1), 1))
    |> raw()
  end

  defp maybe_put_meta_keywords(conn) do
    case get_meta(conn, "keywords") do
      nil ->
        if meta_keywords = Brando.Config.get_site_config("meta_keywords") do
          put_meta(conn, "keywords", meta_keywords)
        else
          conn
        end

      _ ->
        conn
    end
  end

  defp maybe_put_meta_description(conn) do
    case get_meta(conn, "description") do
      nil ->
        if meta_description = Brando.Config.get_site_config("meta_description") do
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
        case Brando.Config.get_site_config("meta_image") do
          nil ->
            conn

          meta_image when is_map(meta_image) ->
            # grab xlarge from img
            img_src = Brando.Utils.img_url(meta_image, :xlarge, prefix: Brando.Utils.media_url())
            img = Path.join("#{conn.scheme}://#{conn.host}", img_src)

            conn
            |> put_meta("image", img)
            |> put_meta("og:image", img)

          meta_image when is_binary(meta_image) ->
            img =
              (String.contains?(meta_image, "://") && meta_image) ||
                Path.join("#{conn.scheme}://#{conn.host}", meta_image)

            conn
            |> put_meta("image", img)
            |> put_meta("og:image", img)
        end

      img ->
        if String.contains?(img, "://") do
          conn
        else
          put_meta(conn, "og:image", Path.join("#{conn.scheme}://#{conn.host}", img))
        end
    end
  end

  @doc """
  Renders opening body tag.

  Checks conn.private for various settings
  """
  def body_tag(conn, opts \\ []) do
    attrs = []
    id = Keyword.get(opts, :id, nil)
    data_script = conn.private[:brando_section_name]
    classes = conn.private[:brando_css_classes]

    attrs = attrs ++ [class: (classes && "#{classes} unloaded") || "unloaded"]
    attrs = (id && attrs ++ [id: id]) || attrs
    attrs = (data_script && attrs ++ [data_script: data_script]) || attrs

    tag(:body, attrs)
  end

  @doc """
  Displays all flash messages in conn
  """
  def display_flash(conn) do
    flash = Phoenix.Controller.get_flash(conn)

    for {type, msg} <- flash do
      """
      <div class="alert alert-block alert-#{type}">
        <a class="close pull-right" data-dismiss="alert" href="#">×</a>
        <i class="fa fa-exclamation-circle m-r-sm"> </i>
        #{msg}
      </div>
      """
      |> raw()
    end
  end

  @doc """
  Outputs an `img` tag marked as safe html

  The `srcset` attribute is the ACTUAL width of the image, as saved to disk. You'll find that in the
  image type's `sizes` map.

  ## Options:

    * `prefix` - string to prefix to the image's url. I.e. `prefix: media_url()`
    * `default` - default value if `image_field` is nil. Does not respect `prefix`, so use
      full path.
    * `cache` - key to cache by, i.e `cache: schema.updated_at`
    * `srcset` - if you want to use the srcset attribute. Set in the form of `{module, field}`.
      I.e `srcset: {Brando.User, :avatar}`
      You can also reference a config struct directly:
      I.e `srcset: image_series.cfg`
      Or supply a srcset directly:
        srcset: %{
          "small" => "300w",
          "medium" => "582w",
          "large" => "936w",
          "xlarge" => "1200w"
        }
    * `attrs` - extra attributes to the tag, ie data attrs
  """
  def img_tag(image_field, size, opts \\ []) do
    lightbox = Keyword.get(opts, :lightbox, false)
    img_src = Brando.Utils.img_url(image_field, size, opts)
    attrs = extract_attrs(image_field, img_src, opts)
    rendered_tag = tag(:img, attrs)
    (lightbox && wrap_lightbox(rendered_tag, img_src)) || rendered_tag
  end

  defp extract_attrs(image_field, img_src, opts) do
    srcset_attr = extract_srcset_attr(image_field, opts)
    sizes_attr = extract_sizes_attr(image_field, opts)
    width_attr = extract_width_attr(image_field, opts)
    height_attr = extract_height_attr(image_field, opts)
    extra_attrs = extract_extra_attr(image_field, opts)

    cleaned_opts =
      Keyword.drop(opts, [:lightbox, :cache, :attrs, :prefix, :srcset, :sizes, :default])

    attrs =
      Keyword.new()
      |> Keyword.put(:src, img_src)
      |> Keyword.merge(
        cleaned_opts ++ sizes_attr ++ srcset_attr ++ width_attr ++ height_attr ++ extra_attrs
      )

    # if we have srcset, set src as empty svg
    (srcset_attr != [] && Keyword.put(attrs, :src, svg_fallback(image_field))) || attrs
  end

  defp extract_srcset_attr(img_field, opts),
    do: (Keyword.get(opts, :srcset) && [srcset: get_srcset(img_field, opts[:srcset], opts)]) || []

  defp extract_sizes_attr(_, opts),
    do: (Keyword.get(opts, :sizes) && [sizes: get_sizes(opts[:sizes])]) || []

  defp extract_width_attr(img_field, opts),
    do: (Keyword.get(opts, :width) && [width: Map.get(img_field, :width)]) || []

  defp extract_height_attr(img_field, opts),
    do: (Keyword.get(opts, :height) && [height: Map.get(img_field, :height)]) || []

  defp extract_extra_attr(_, opts), do: Keyword.get(opts, :attrs, [])

  defp wrap_lightbox(rendered_tag, img_src),
    do: content_tag(:a, rendered_tag, href: img_src, data_lightbox: img_src)

  @doc """
  Replaces all newlines with HTML break elements.
  """
  def nl2br(text), do: String.replace(text, "\n", "<br>")

  @doc """
  Outputs a `picture` tag with source, img and a noscript fallback

  The `srcset` attribute is the ACTUAL width of the image, as saved to disk. You'll find that in the
  image type's `sizes` map.

  ## Options:

    * `prefix` - string to prefix to the image's url. I.e. `prefix: media_url()`
    * `picture_class` - class added to the picture root element
    * `img_class` - class added to the img element. I.e img_class: "img-fluid"
    * `srcset` - if you want to use the srcset attribute. Set in the form of `{module, field}`.
      I.e `srcset: {Brando.User, :avatar}`
      You can also reference a config struct directly:
      I.e `srcset: image_series.cfg`
      Or supply a srcset directly:
        srcset: %{
          "small" => "300w",
          "medium" => "582w",
          "large" => "936w",
          "xlarge" => "1200w"
        }
      Or a list of srcsets to generate multiple source elements
  """
  @spec picture_tag(Map.t(), keyword()) :: {:safe, [...]}
  def picture_tag(img_struct, opts \\ []) do
    initial_map = %{
      img: [],
      picture: [],
      source: [],
      noscript_img: [],
      mq_sources: [],
      opts: opts
    }

    attrs =
      initial_map
      |> add_lazyload()
      |> add_sizes()
      |> add_alt()
      |> add_srcset(img_struct)
      |> add_mq(img_struct)
      |> add_dims(img_struct)
      |> add_src(img_struct)
      |> add_classes()
      |> add_moonwalk()

    img_tag = tag(:img, attrs.img)
    noscript_img_tag = tag(:img, attrs.noscript_img)

    source_tag =
      if Enum.all?(attrs.source, fn {_k, v} -> v == false end) do
        ""
      else
        tag(:source, attrs.source)
      end

    mq_source_tags = attrs.mq_sources
    noscript_tag = content_tag(:noscript, noscript_img_tag)

    picture_tag =
      content_tag(:picture, [mq_source_tags, source_tag, img_tag, noscript_tag], attrs.picture)

    lightbox = Keyword.get(opts, :lightbox, false)
    (lightbox && wrap_lightbox(picture_tag, attrs.src)) || picture_tag
  end

  defp add_alt(attrs) do
    alt = Keyword.get(attrs.opts, :alt, "")

    put_in(attrs, [:img, :alt], alt)
  end

  defp add_lazyload(attrs) do
    attrs = Map.put(attrs, :lazyload, Keyword.get(attrs.opts, :lazyload, false))
    # We want width and height keys when we lazyload
    put_in(attrs.opts, Keyword.merge(attrs.opts, width: true, height: true))
  end

  defp add_classes(%{lazyload: lazyload} = attrs) do
    img_class = Keyword.get(attrs.opts, :img_class, false)
    picture_class = Keyword.get(attrs.opts, :picture_class, false)

    attrs
    |> put_in([:picture, :class], picture_class)
    |> put_in([:img, :class], img_class)
    |> put_in(
      [:img, :data_ll_image],
      lazyload && !Keyword.get(attrs.picture, :data_ll_srcset, false)
    )
  end

  defp add_sizes(attrs) do
    sizes = (Keyword.get(attrs.opts, :sizes) && get_sizes(attrs.opts[:sizes])) || false

    attrs
    |> put_in([:img, :sizes], sizes)
    |> put_in([:source, :sizes], sizes)
  end

  defp add_srcset(%{lazyload: true} = attrs, img_struct) do
    srcset =
      (Keyword.get(attrs.opts, :srcset) && get_srcset(img_struct, attrs.opts[:srcset], attrs.opts)) ||
        false

    placeholder_srcset =
      (Keyword.get(attrs.opts, :srcset) &&
         get_srcset(img_struct, attrs.opts[:srcset], attrs.opts, :placeholder)) ||
        false

    attrs
    |> put_in([:picture, :data_ll_srcset], !!srcset)
    |> put_in([:img, :srcset], placeholder_srcset)
    |> put_in([:img, :data_ll_placeholder], !!placeholder_srcset)
    |> put_in([:img, :data_srcset], srcset)
    |> put_in([:source, :srcset], placeholder_srcset)
    |> put_in([:source, :data_srcset], srcset)
  end

  defp add_srcset(%{lazyload: false} = attrs, img_struct) do
    srcset =
      (Keyword.get(attrs.opts, :srcset) && get_srcset(img_struct, attrs.opts[:srcset], attrs.opts)) ||
        false

    attrs
    |> put_in([:img, :srcset], srcset)
    |> put_in([:img, :data_srcset], false)
    |> put_in([:source, :srcset], srcset)
    |> put_in([:source, :data_srcset], false)
  end

  defp add_mq(%{lazyload: _} = attrs, img_struct) do
    case (Keyword.get(attrs.opts, :media_queries) &&
            get_mq(img_struct, attrs.opts[:media_queries], attrs.opts)) ||
           false do
      false ->
        attrs

      mqs ->
        tags =
          Enum.map(mqs, fn {media_query, srcset} ->
            tag(:source, media: media_query, srcset: srcset)
          end)

        attrs
        |> put_in([:mq_sources], tags)
    end
  end

  defp add_src(%{lazyload: true} = attrs, img_struct) do
    key = Keyword.get(attrs.opts, :key) || :xlarge
    src = Brando.Utils.img_url(img_struct, key, attrs.opts)
    fallback = svg_fallback(img_struct, 0.05)

    attrs
    |> put_in([:img, :src], fallback)
    |> put_in([:img, :data_src], src)
    |> put_in([:noscript_img, :src], src)
    |> Map.put(:src, src)
  end

  defp add_src(%{lazyload: false} = attrs, img_struct) do
    key = Keyword.get(attrs.opts, :key) || :xlarge
    src = Brando.Utils.img_url(img_struct, key, attrs.opts)

    attrs
    |> put_in([:img, :src], src)
    |> put_in([:img, :data_src], false)
    |> put_in([:noscript_img, :src], src)
  end

  defp add_dims(attrs, img_struct) do
    width = (Keyword.get(attrs.opts, :width) && Map.get(img_struct, :width)) || false
    height = (Keyword.get(attrs.opts, :height) && Map.get(img_struct, :height)) || false

    attrs
    |> put_in([:img, :width], width)
    |> put_in([:img, :height], height)
  end

  defp add_moonwalk(attrs) do
    moonwalk = Keyword.get(attrs.opts, :moonwalk, false)
    put_in(attrs, [:picture, :moonwalk], moonwalk)
  end

  @doc """
  Calculate image ratio
  """
  def ratio(%{height: height, width: width})
      when is_nil(height) or is_nil(width),
      do: 0

  def ratio(%{height: height, width: width}) do
    Decimal.new(height)
    |> Decimal.div(Decimal.new(width))
    |> Decimal.mult(Decimal.new(100))
  end

  def ratio(nil), do: 0

  @doc """
  Return a correctly sized svg fallback
  """
  def svg_fallback(image_field, opacity \\ 0) do
    width = Map.get(image_field, :width, 0)
    height = Map.get(image_field, :height, 0)

    "data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%27http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg" <>
      "%27%20width%3D%27#{width}%27%20height%3D%27#{height}%27" <>
      "%20style%3D%27background%3Argba%280%2C0%2C0%2C#{opacity}%29%27%2F%3E"
  end

  @doc """
  Get sizes from image config
  """
  def get_sizes(nil), do: nil
  def get_sizes(sizes) when is_list(sizes), do: Enum.join(sizes, ", ")

  def get_sizes(_),
    do:
      raise(ArgumentError,
        message: ~s<sizes key must be a list: ["(min-width: 36em) 33.3vw", "100vw"]>
      )

  @doc """
  Get srcset from image config
  """
  def get_srcset(image_field, cfg, opts, placeholder \\ false)
  def get_srcset(_, nil, _, _), do: nil

  def get_srcset(image_field, {mod, field}, opts, placeholder) do
    {:ok, cfg} = apply(mod, :get_image_cfg, [field])

    if !cfg.srcset do
      raise ArgumentError,
        message: "no `:srcset` key set in #{inspect(mod)}'s #{inspect(field)} image config"
    end

    srcset_values =
      for {k, v} <- cfg.srcset do
        path = Brando.Utils.img_url(image_field, (placeholder && "micro") || k, opts)
        "#{path} #{v}"
      end

    Enum.join(srcset_values, ", ")
  end

  def get_srcset(image_field, %Brando.Type.ImageConfig{} = cfg, opts, placeholder) do
    if !cfg.srcset do
      raise ArgumentError, message: "no `:srcset` key set in supplied image config"
    end

    srcset = sort_srcset(cfg.srcset)

    srcset_values =
      for {k, v} <- srcset do
        path = Brando.Utils.img_url(image_field, (placeholder && "micro") || k, opts)
        "#{path} #{v}"
      end

    Enum.join(srcset_values, ", ")
  end

  def get_srcset(image_field, srcset, opts, placeholder) do
    srcset_values =
      for {k, v} <- srcset do
        path = Brando.Utils.img_url(image_field, (placeholder && "micro") || k, opts)
        "#{path} #{v}"
      end

    Enum.join(srcset_values, ", ")
  end

  def get_mq(image_field, mq, opts) do
    for {media_query, srcsets} <- mq do
      rendered_srcsets =
        Enum.map(srcsets, fn {k, v} ->
          path = Brando.Utils.img_url(image_field, k, opts)
          "#{path} #{v}"
        end)

      {media_query, Enum.join(rendered_srcsets, ", ")}
    end
  end

  defp sort_srcset(map) when is_map(map) do
    Map.to_list(map)
    |> Enum.sort(fn {_k1, s1}, {_k2, s2} ->
      t1 =
        s1
        |> String.replace("w", "")
        |> String.replace("h", "")
        |> String.replace("wv", "")
        |> String.replace("hv", "")
        |> String.to_integer()

      t2 =
        s2
        |> String.replace("w", "")
        |> String.replace("h", "")
        |> String.replace("wv", "")
        |> String.replace("hv", "")
        |> String.to_integer()

      t1 > t2
    end)
  end

  defp sort_srcset(list), do: list
end
