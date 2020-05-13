defmodule Brando.HTML.Images do
  @moduledoc """
  HTML functions for rendering image/picture tags
  """

  alias Brando.Utils
  import Phoenix.HTML.Tag

  @doc """
  Outputs a `picture` tag with source, img and a noscript fallback

  The `srcset` attribute is the ACTUAL width of the image, as saved to disk. You'll find that in the
  image type's `sizes` map.

  ## Options:

    * `lazyload` - whether to lazyload picture or not
    * `prefix` - string to prefix to the image's url. I.e. `prefix: media_url()`
    * `picture_class` - class added to the picture root element
    * `picture_attrs` - list of attributes to add to picture element. I.e picture_attrs: [data_test: true]
    * `placeholder` - for lazyloading. :svg for svg placeholder -- :micro for blur-up -- :none for nothing
    * `img_class` - class added to the img element. I.e img_class: "img-fluid"
    * `img_attrs` - list of attributes to add to img element. I.e img_attrs: [data_test: true]
    * `media_queries` - list of media queries to add to source.
    * `cache` - key to cache by, i.e `cache: schema.updated_at`
      I.e `media_queries: [{"(min-width: 0px) and (max-width: 760px)", [{"mobile", "700w"}]}]`
    * `srcset` - if you want to use the srcset attribute. Set in the form of `{module, field}`.
      I.e `srcset: {Brando.Users.User, :avatar}`

      You can also reference a config struct:
      I.e `srcset: image_series.cfg`

      Or supply a srcset directly:
        srcset: %{
          "small" => "300w",
          "medium" => "582w",
          "large" => "936w",
          "xlarge" => "1200w"
        }

      Or a list of srcsets to generate multiple source elements:

  """

  @spec picture_tag(Map.t(), keyword()) :: {:safe, [...]}
  def picture_tag(img_struct, opts \\ [])

  def picture_tag(%Brando.Type.Image{} = img_struct, opts) do
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
      |> add_attrs()
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

  # when we're not given a struct
  def picture_tag(img_map, opts) do
    img_struct = Utils.stringy_struct(Brando.Type.Image, img_map)
    picture_tag(img_struct, opts)
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

  defp add_attrs(attrs) do
    img_attrs = Keyword.get(attrs.opts, :img_attrs, [])
    picture_attrs = Keyword.get(attrs.opts, :picture_attrs, [])

    attrs = Enum.reduce(img_attrs, attrs, fn {k, v}, acc -> put_in(acc, [:img, k], v) end)
    Enum.reduce(picture_attrs, attrs, fn {k, v}, acc -> put_in(acc, [:picture, k], v) end)
  end

  defp add_sizes(attrs) do
    sizes = (Keyword.get(attrs.opts, :sizes) && get_sizes(attrs.opts[:sizes])) || false

    attrs
    |> put_in([:img, :sizes], sizes)
    |> put_in([:source, :sizes], sizes)
  end

  defp add_srcset(%{lazyload: true} = attrs, img_struct) do
    placeholder = Keyword.get(attrs.opts, :placeholder, false)

    no_srcset_placeholder =
      case placeholder do
        :svg -> true
        false -> true
        _ -> false
      end

    srcset =
      (Keyword.get(attrs.opts, :srcset) && get_srcset(img_struct, attrs.opts[:srcset], attrs.opts)) ||
        false

    placeholder_srcset =
      (Keyword.get(attrs.opts, :srcset) &&
         get_srcset(img_struct, attrs.opts[:srcset], attrs.opts, placeholder)) ||
        false

    attrs
    |> put_in([:picture, :data_ll_srcset], !!srcset)
    |> put_in([:img, :srcset], if(no_srcset_placeholder, do: false, else: placeholder_srcset))
    |> put_in([:img, :data_ll_placeholder], !!placeholder_srcset)
    |> put_in([:img, :data_srcset], srcset)
    |> put_in([:source, :srcset], if(no_srcset_placeholder, do: false, else: placeholder_srcset))
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
    placeholder = Keyword.get(attrs.opts, :placeholder, false)

    key = Keyword.get(attrs.opts, :key) || :xlarge
    src = Utils.img_url(img_struct, key, attrs.opts)

    fallback =
      case placeholder do
        :svg -> svg_fallback(img_struct, 0.05, attrs.opts)
        false -> false
        _ -> Utils.img_url(img_struct, placeholder, attrs.opts)
      end

    attrs
    |> put_in([:img, :src], fallback)
    |> put_in([:img, :data_src], src)
    |> put_in([:noscript_img, :src], src)
    |> Map.put(:src, src)
  end

  defp add_src(%{lazyload: false} = attrs, img_struct) do
    key = Keyword.get(attrs.opts, :key) || :xlarge
    src = Utils.img_url(img_struct, key, attrs.opts)

    attrs
    |> put_in([:img, :src], src)
    |> put_in([:img, :data_src], false)
    |> put_in([:noscript_img, :src], src)
  end

  # automatically add dims when lazyload: true
  defp add_dims(%{lazyload: true} = attrs, img_struct) do
    width =
      case Keyword.fetch(attrs.opts, :width) do
        :error ->
          false

        {:ok, true} ->
          Map.get(img_struct, :width)

        {:ok, width} ->
          width
      end

    height =
      case Keyword.fetch(attrs.opts, :height) do
        :error ->
          false

        {:ok, true} ->
          Map.get(img_struct, :height)

        {:ok, height} ->
          height
      end

    orientation = (width > height && "landscape") || "portrait"

    attrs
    |> put_in([:img, :width], width)
    |> put_in([:img, :height], height)
    |> put_in([:picture, :data_orientation], orientation)
  end

  defp add_dims(attrs, img_struct) do
    width =
      case Keyword.fetch(attrs.opts, :width) do
        :error ->
          false

        {:ok, true} ->
          Map.get(img_struct, :width)

        {:ok, width} ->
          width
      end

    height =
      case Keyword.fetch(attrs.opts, :height) do
        :error ->
          false

        {:ok, true} ->
          Map.get(img_struct, :height)

        {:ok, height} ->
          height
      end

    orientation = (width > height && "landscape") || "portrait"

    attrs
    |> put_in([:img, :width], width)
    |> put_in([:img, :height], height)
    |> put_in([:picture, :data_orientation], orientation)
  end

  defp add_moonwalk(attrs) do
    moonwalk = Keyword.get(attrs.opts, :moonwalk, false)
    put_in(attrs, [:picture, :data_moonwalk], moonwalk)
  end

  defp wrap_lightbox(rendered_tag, img_src),
    do: content_tag(:a, rendered_tag, href: img_src, data_lightbox: img_src)

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
      I.e `srcset: {Brando.Users.User, :avatar}`
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
    img_src = Utils.img_url(image_field, size, opts)
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
      Keyword.drop(opts, [
        :lightbox,
        :cache,
        :attrs,
        :prefix,
        :srcset,
        :sizes,
        :default,
        :width,
        :height
      ])

    attrs =
      Keyword.new()
      |> Keyword.put(:src, img_src)
      |> Keyword.merge(
        cleaned_opts ++ sizes_attr ++ srcset_attr ++ width_attr ++ height_attr ++ extra_attrs
      )

    # if we have srcset, set src as empty svg
    (srcset_attr != [] && Keyword.put(attrs, :src, svg_fallback(image_field, 0, attrs))) || attrs
  end

  defp extract_srcset_attr(img_field, opts),
    do: (Keyword.get(opts, :srcset) && [srcset: get_srcset(img_field, opts[:srcset], opts)]) || []

  defp extract_sizes_attr(_, opts),
    do: (Keyword.get(opts, :sizes) && [sizes: get_sizes(opts[:sizes])]) || []

  defp extract_width_attr(img_field, opts) do
    case Keyword.fetch(opts, :width) do
      :error ->
        []

      {:ok, true} ->
        [width: Map.get(img_field, :width)]

      {:ok, width} ->
        [width: width]
    end
  end

  defp extract_height_attr(img_field, opts) do
    case Keyword.fetch(opts, :height) do
      :error ->
        []

      {:ok, true} ->
        [height: Map.get(img_field, :height)]

      {:ok, height} ->
        [height: height]
    end
  end

  defp extract_extra_attr(_, opts), do: Keyword.get(opts, :attrs, [])

  @doc """
  Return a correctly sized svg fallback
  """
  def svg_fallback(image_field, opacity \\ 0, attrs \\ []) do
    width =
      case Keyword.fetch(attrs, :width) do
        :error ->
          Map.get(image_field, :width, 0)

        {:ok, true} ->
          Map.get(image_field, :width, 0)

        {:ok, width} ->
          width
      end

    height =
      case Keyword.fetch(attrs, :height) do
        :error ->
          Map.get(image_field, :height, 0)

        {:ok, true} ->
          Map.get(image_field, :height, 0)

        {:ok, height} ->
          height
      end

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
        path = Utils.img_url(image_field, (placeholder !== :svg && placeholder) || k, opts)
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
        path = Utils.img_url(image_field, (placeholder !== :svg && placeholder) || k, opts)
        "#{path} #{v}"
      end

    Enum.join(srcset_values, ", ")
  end

  def get_srcset(image_field, srcset, opts, placeholder) do
    srcset_values =
      for {k, v} <- srcset do
        path = Utils.img_url(image_field, (placeholder !== :svg && placeholder) || k, opts)
        "#{path} #{v}"
      end

    Enum.join(srcset_values, ", ")
  end

  def get_mq(image_field, mq, opts) do
    for {media_query, srcsets} <- mq do
      rendered_srcsets =
        Enum.map(srcsets, fn {k, v} ->
          path = Utils.img_url(image_field, k, opts)
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
