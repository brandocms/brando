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
    * `placeholder` - for lazyloading.
      - :svg for svg placeholder
      - :dominant_color
      - :micro for blur-up
      - :none for nothing
    * `img_class` - class added to the img element. I.e img_class: "img-fluid"
    * `img_attrs` - list of attributes to add to img element. I.e img_attrs: [data_test: true]
    * `cache` - key to cache by, i.e `cache: schema.updated_at`
    * `media_queries` - list of media queries to add to source.
       I.e `media_queries: [{"(min-width: 0px) and (max-width: 760px)", [{"mobile", "700w"}]}]`
    * `sizes` - set to "auto" for adding `data-sizes="auto"` which Jupiter parses and updates to image's size.
       You can also set as a list of sizes: `["30vw"]`
    * `srcset` - if you want to use the srcset attribute. Set in the form of `{module, field}`.
      I.e `srcset: {Brando.Users.User, :avatar}`

      Or with a key:
      I.e `srcset: {Brando.Users.User, :avatar, :cropped_key}`

      You can also reference a config struct:
      I.e `srcset: image_series.cfg`

      Or supply a srcset directly:
        srcset: [
          {"small", "300w"},
          {"medium", "582w"},
          {"large", "936w"},
          {"xlarge", "1200w"}
        ]

      Or a list of srcsets to generate multiple source elements:

  """

  @spec picture_tag(map, keyword()) :: {:safe, [...]}
  def picture_tag(image_struct, opts \\ [])

  def picture_tag(%Brando.Type.Image{} = image_struct, opts) do
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
      |> add_type(image_struct)
      |> add_alt(image_struct)
      |> add_srcset(image_struct)
      |> add_mq(image_struct)
      |> add_dims(image_struct)
      |> add_src(image_struct)
      |> add_dominant_color(image_struct)
      |> add_attrs()
      |> add_classes()
      |> add_moonwalk()

    img_tag = tag(:img, attrs.img)
    source_tag = build_source_tags(image_struct, attrs)

    figcaption_tag =
      if Keyword.get(opts, :caption) && image_struct.title && image_struct.title != "" do
        content_tag(:figcaption, image_struct.title)
      else
        ""
      end

    mq_source_tags = attrs.mq_sources

    noscript_alt = Keyword.get(attrs.opts, :alt, Map.get(image_struct, :alt, ""))
    noscript_img_tag = tag(:img, attrs.noscript_img ++ [alt: noscript_alt])
    noscript_tag = content_tag(:noscript, noscript_img_tag)

    picture_tag =
      content_tag(
        :picture,
        [mq_source_tags, source_tag, img_tag, figcaption_tag, noscript_tag],
        attrs.picture
      )

    if Keyword.get(opts, :lightbox, false) do
      wrap_lightbox(
        picture_tag,
        Keyword.get(attrs.img, (Keyword.get(opts, :lazyload) && :data_src) || :src),
        Keyword.get(attrs.img, :data_srcset)
      )
    else
      picture_tag
    end
  end

  # when we receive a base64 from vue. This is for live preview, when we
  # do not have a stored copy of the image.
  def picture_tag(%{"base64" => base64}, _opts) do
    content_tag(:picture, tag(:img, src: base64))
  end

  # when we're not given a struct
  def picture_tag(img_map, opts) do
    #! TODO: this is very hacky, but only a stopgap until we do away
    #! with `prefix` media_url's entirely

    opts =
      if img_map["original"] && String.starts_with?(img_map["original"], "/media") do
        Keyword.drop(opts, [:prefix])
      else
        opts
      end

    image_struct = Utils.stringy_struct(Brando.Type.Image, img_map)
    picture_tag(image_struct, opts)
  end

  defp build_source_tags(%{webp: true}, attrs) do
    # if all source attrs are false (except type, which we don't care about)
    # drop the source tag
    if Enum.all?(Keyword.drop(attrs.source, [:type]), fn {_k, v} -> v == false end) do
      ""
    else
      [tag(:source, webp_attrs(attrs.source)), tag(:source, attrs.source)]
    end
  end

  defp build_source_tags(_, attrs) do
    # if all source attrs are false (except type, which we don't care about)
    # drop the source tag
    if Enum.all?(Keyword.drop(attrs.source, [:type]), fn {_k, v} -> v == false end) do
      ""
    else
      tag(:source, attrs.source)
    end
  end

  defp webp_attrs(source_attrs) do
    Enum.map(source_attrs, fn
      {:data_srcset, v} -> {:data_srcset, suffix_srcs(v, ".webp")}
      {:srcset, v} -> {:srcset, suffix_srcs(v, ".webp")}
      {:type, _} -> {:type, "image/webp"}
      {k, v} -> {k, v}
    end)
  end

  defp suffix_srcs(false, _), do: false
  defp suffix_srcs(srcs, suffix), do: String.replace(srcs, [".jpg", ".jpeg", ".png"], suffix)

  defp add_alt(attrs, image_struct) do
    alt = Keyword.get(attrs.opts, :alt, Map.get(image_struct, :alt, ""))

    put_in(attrs, [:img, :alt], alt)
  end

  defp add_lazyload(attrs) do
    attrs = Map.put(attrs, :lazyload, Keyword.get(attrs.opts, :lazyload, false))

    # We want width and height keys when we lazyload
    if attrs.lazyload do
      put_in(attrs.opts, Keyword.merge(attrs.opts, width: true, height: true))
    else
      attrs
    end
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
    |> put_in(
      [:img, :data_ll_srcset_image],
      lazyload && Keyword.get(attrs.picture, :data_ll_srcset, false)
    )
  end

  defp add_attrs(attrs) do
    img_attrs = Keyword.get(attrs.opts, :img_attrs, [])
    picture_attrs = Keyword.get(attrs.opts, :picture_attrs, [])

    attrs = Enum.reduce(img_attrs, attrs, fn {k, v}, acc -> put_in(acc, [:img, k], v) end)
    Enum.reduce(picture_attrs, attrs, fn {k, v}, acc -> put_in(acc, [:picture, k], v) end)
  end

  defp add_sizes(attrs) do
    {data_sizes, sizes} =
      case Keyword.get(attrs.opts, :sizes) do
        "auto" -> {"auto", false}
        nil -> {false, false}
        val -> {false, get_sizes(val)}
      end

    attrs
    |> put_in([:img, :sizes], sizes)
    |> put_in([:img, :data_sizes], data_sizes)
    |> put_in([:source, :sizes], sizes)
  end

  defp add_type(attrs, %{sizes: nil}), do: attrs
  defp add_type(attrs, %{sizes: sizes}) when sizes == %{}, do: attrs

  defp add_type(attrs, %{sizes: sizes}) do
    type =
      case sizes |> Map.values() |> List.first() |> Path.extname() do
        ".jpg" -> "image/jpeg"
        ".jpeg" -> "image/jpeg"
        ".png" -> "image/png"
        ".gif" -> "image/gif"
        _ -> nil
      end

    if type do
      put_in(attrs, [:source, :type], type)
    else
      attrs
    end
  end

  defp add_type(attrs, _), do: attrs

  defp add_srcset(%{lazyload: true} = attrs, image_struct) do
    placeholder = Keyword.get(attrs.opts, :placeholder, false)

    no_srcset_placeholder = srcset_placeholder?(placeholder)

    {cropped_ratio, srcset} =
      (Keyword.get(attrs.opts, :srcset) &&
         get_srcset(image_struct, attrs.opts[:srcset], attrs.opts)) ||
        {false, false}

    {_, placeholder_srcset} =
      (Keyword.get(attrs.opts, :srcset) &&
         get_srcset(image_struct, attrs.opts[:srcset], attrs.opts, placeholder)) ||
        {false, false}

    attrs
    |> Map.put(:cropped_ratio, cropped_ratio)
    |> put_in([:picture, :data_ll_srcset], !!srcset)
    |> put_in([:img, :srcset], if(no_srcset_placeholder, do: false, else: placeholder_srcset))
    |> put_in([:img, :data_ll_placeholder], !!placeholder_srcset)
    |> put_in([:img, :data_srcset], srcset)
    |> put_in([:source, :srcset], if(no_srcset_placeholder, do: false, else: placeholder_srcset))
    |> put_in([:source, :data_srcset], srcset)
  end

  defp add_srcset(%{lazyload: false} = attrs, image_struct) do
    {cropped_ratio, srcset} =
      (Keyword.get(attrs.opts, :srcset) &&
         get_srcset(image_struct, attrs.opts[:srcset], attrs.opts)) ||
        {false, false}

    attrs
    |> Map.put(:cropped_ratio, cropped_ratio)
    |> put_in([:img, :srcset], srcset)
    |> put_in([:img, :data_srcset], false)
    |> put_in([:source, :srcset], srcset)
    |> put_in([:source, :data_srcset], false)
  end

  defp srcset_placeholder?(:svg), do: true
  defp srcset_placeholder?(:dominant_color), do: true
  defp srcset_placeholder?(false), do: true
  defp srcset_placeholder?(_), do: false

  defp add_mq(%{lazyload: _} = attrs, image_struct) do
    case (Keyword.get(attrs.opts, :media_queries) &&
            get_mq(image_struct, attrs.opts[:media_queries], attrs.opts)) ||
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

  defp add_src(%{lazyload: true} = attrs, image_struct) do
    placeholder = Keyword.get(attrs.opts, :placeholder, false)

    key = Keyword.get(attrs.opts, :key) || :small
    src = Utils.img_url(image_struct, key, attrs.opts)

    fallback =
      case placeholder do
        :svg -> svg_fallback(image_struct, 0.05, attrs.opts)
        :dominant_color -> svg_fallback(image_struct, 0, attrs.opts)
        false -> false
        _ -> Utils.img_url(image_struct, placeholder, attrs.opts)
      end

    attrs
    |> put_in([:img, :src], fallback)
    |> put_in([:img, :data_src], src)
    |> put_in([:noscript_img, :src], src)
    |> Map.put(:src, src)
  end

  defp add_src(%{lazyload: false} = attrs, image_struct) do
    key = Keyword.get(attrs.opts, :key) || :xlarge
    src = Utils.img_url(image_struct, key, attrs.opts)

    attrs
    |> put_in([:img, :src], src)
    |> put_in([:img, :data_src], false)
    |> put_in([:noscript_img, :src], src)
  end

  defp add_dominant_color(attrs, image_struct) do
    case Keyword.get(attrs.opts, :placeholder) do
      :dominant_color ->
        attrs
        |> put_in(
          [:picture, :style],
          "background-color: #{image_struct.dominant_color || "transparent"}"
        )

      _ ->
        attrs
    end
  end

  defp add_dims(%{cropped_ratio: false} = attrs, image_struct) do
    img_width = Map.get(image_struct, :width)
    img_height = Map.get(image_struct, :height)

    width =
      case Keyword.fetch(attrs.opts, :width) do
        :error ->
          false

        {:ok, true} ->
          Map.get(image_struct, :width)

        {:ok, width} ->
          width
      end

    height =
      case Keyword.fetch(attrs.opts, :height) do
        :error ->
          false

        {:ok, true} ->
          Map.get(image_struct, :height)

        {:ok, height} ->
          height
      end

    orientation = Brando.Images.get_image_orientation(img_width, img_height)

    attrs
    |> put_in([:img, :width], width)
    |> put_in([:img, :height], height)
    |> put_in([:picture, :data_orientation], orientation)
  end

  defp add_dims(%{cropped_ratio: cropped_ratio} = attrs, image_struct) do
    img_width = Map.get(image_struct, :width)
    img_height = Map.get(image_struct, :height)

    width =
      case img_width do
        nil ->
          false

        width ->
          width
      end

    height =
      case img_height do
        nil ->
          false

        _ ->
          round(width / cropped_ratio)
      end

    orientation = Brando.Images.get_image_orientation(width, height)

    attrs
    |> put_in([:img, :width], width)
    |> put_in([:img, :height], height)
    |> put_in([:picture, :data_orientation], orientation)
  end

  defp add_moonwalk(attrs) do
    moonwalk = Keyword.get(attrs.opts, :moonwalk, false)
    put_in(attrs, [:picture, :data_moonwalk], moonwalk)
  end

  defp wrap_lightbox(rendered_tag, img_src, srcset \\ nil),
    do: content_tag(:a, rendered_tag, href: img_src, data_srcset: srcset, data_lightbox: img_src)

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
        srcset: [
          {"small", "300w"},
          {"medium", "582w"},
          {"large", "936w"},
          {"xlarge", "1200w"}
        ]
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
    do:
      (Keyword.get(opts, :srcset) &&
         [srcset: get_srcset(img_field, opts[:srcset], opts) |> elem(1)]) || []

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
  def get_srcset(_, nil, _, _), do: {false, nil}

  def get_srcset(image_field, srcset, opts, placeholder) when is_binary(srcset) do
    [module_string, field_string] = String.split(srcset, ":")
    module = Module.concat([module_string])

    case String.split(field_string, ".") do
      [field, key] ->
        get_srcset(
          image_field,
          {module, String.to_existing_atom(field), String.to_existing_atom(key)},
          opts,
          placeholder
        )

      [field] ->
        get_srcset(image_field, {module, String.to_existing_atom(field)}, opts, placeholder)
    end
  end

  def get_srcset(image_field, {mod, field}, opts, placeholder) do
    #! TODO Remove this when we move to Blueprints completely
    {:ok, cfg} =
      if {:get_image_cfg, 1} in mod.__info__(:functions) do
        apply(mod, :get_image_cfg, [field])
      else
        {:ok, apply(mod, :__attribute_opts__, [field])}
      end

    #! END

    if !cfg.srcset do
      raise ArgumentError,
        message: "no `:srcset` key set in #{inspect(mod)}'s #{inspect(field)} image config"
    end

    srcset_values =
      for {k, v} <- cfg.srcset do
        path =
          Utils.img_url(
            image_field,
            (placeholder not in [:svg, :dominant_color] && placeholder) || k,
            opts
          )

        "#{path} #{v}"
      end

    {false, Enum.join(srcset_values, ", ")}
  end

  # this is for srcsets with keys:
  #
  # srcset: %{
  #   regular: [
  #     {"small", "700w"},
  #     {"medium", "1100w"},
  #     {"large", "1700w"},
  #     {"xlarge", "2100w"}
  #   ],
  #   cropped: [
  #     {"small_crop", "700w"},
  #     {"medium_crop", "1100w"}
  #   ]
  # }
  def get_srcset(image_field, {mod, field, key}, opts, placeholder) do
    #! TODO Remove this when we move to Blueprints completely
    {:ok, cfg} =
      if {:get_image_cfg, 1} in mod.__info__(:functions) do
        apply(mod, :get_image_cfg, [field])
      else
        {:ok, apply(mod, :__attribute_opts__, [field])}
      end

    #! END

    if !cfg.srcset do
      raise ArgumentError,
        message: "no `:srcset` key set in #{inspect(mod)}'s #{inspect(field)} image config"
    end

    # check if it is cropped
    cropped_ratio = check_cropped(cfg, key)

    srcset_values =
      for {k, v} <- Map.get(cfg.srcset, key) do
        path =
          Utils.img_url(
            image_field,
            (placeholder not in [:svg, :dominant_color] && placeholder) || k,
            opts
          )

        "#{path} #{v}"
      end

    {cropped_ratio, Enum.join(srcset_values, ", ")}
  end

  def get_srcset(image_field, %Brando.Type.ImageConfig{} = cfg, opts, placeholder) do
    if !cfg.srcset do
      raise ArgumentError, message: "no `:srcset` key set in supplied image config"
    end

    srcset = sort_srcset(cfg.srcset)

    srcset_values =
      for {k, v} <- srcset do
        path =
          Utils.img_url(
            image_field,
            (placeholder not in [:svg, :dominant_color] && placeholder) || k,
            opts
          )

        "#{path} #{v}"
      end

    {false, Enum.join(srcset_values, ", ")}
  end

  def get_srcset(image_field, srcset, opts, placeholder) do
    srcset_values =
      for {k, v} <- srcset do
        path =
          Utils.img_url(
            image_field,
            (placeholder not in [:svg, :dominant_color] && placeholder) || k,
            opts
          )

        "#{path} #{v}"
      end

    {false, Enum.join(srcset_values, ", ")}
  end

  defp check_cropped(%{sizes: sizes, srcset: srcset}, key) do
    string_key = to_string(key)

    if String.contains?(string_key, "crop") do
      cropped_srcset = Map.get(srcset, key)

      cfg_key_to_check =
        cropped_srcset
        |> List.last()
        |> elem(0)

      size = Map.get(sizes, cfg_key_to_check)

      calc_ratio(size)
    else
      false
    end
  end

  defp calc_ratio(%{"ratio" => ratio}) do
    [w, h] =
      ratio
      |> String.split("/")
      |> Enum.map(&String.to_integer/1)

    Kernel./(w, h)
  end

  defp calc_ratio(%{"size" => size}) do
    [w, h] =
      size
      |> String.split("x")
      |> Enum.map(&String.to_integer/1)

    Kernel./(w, h)
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
