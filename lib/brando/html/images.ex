defmodule Brando.HTML.Images do
  @moduledoc """
  HTML functions for rendering image/picture tags
  """

  use Phoenix.Component
  alias Brando.Utils

  @doc """
  Outputs a `picture` tag with source, img and a noscript fallback

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
    * `moonwalk` - set moonwalk attr
    * `media_queries` - list of media queries to add to source.
       I.e `media_queries: [{"(min-width: 0px) and (max-width: 760px)", [{"mobile", "700w"}]}]`
    * `sizes` - set to "auto" for adding `data-sizes="auto"` which Jupiter parses and updates to image's size.
       You can also set as a list of sizes: `["30vw"]`
    * `srcset` - if you want to use the srcset attribute. Set in the form of `{module, field}`.
      I.e `srcset: {Brando.Users.User, :avatar}`

      Or with a key:
      I.e `srcset: {Brando.Users.User, :avatar, :cropped_key}`

      Or with a string:
      I.e `srcset: "Brando.Users.User:avatar.cropped"`

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
  def picture(%{src: nil} = assigns) do
    ~H||
  end

  def picture(%{src: %Ecto.Association.NotLoaded{}} = assigns) do
    ~H"""
    <div>
      <code>
        Trying to call `picture` tag on an unloaded association<br><br>
        <%= inspect(@src, structs: false, pretty: true) %>
      </code>
    </div>
    """
  end

  def picture(%{src: %Brando.Content.Var.Image{} = var} = assigns) do
    assigns = assign(assigns, src: var.value)
    picture(assigns)
  end

  def picture(%{src: %{path: ""}} = assigns) do
    ~H""
  end

  def picture(%{src: %struct_type{} = image_struct, opts: opts} = assigns)
      when struct_type in [Brando.Images.Image, Brando.Villain.Blocks.PictureBlock.Data] do
    initial_map = %{
      img: [],
      picture: [],
      figure: [],
      source: [],
      noscript_img: [],
      mq_sources: [],
      opts: opts
    }

    attrs =
      initial_map
      |> add_original_type(image_struct)
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

    lightbox_src = Map.get(attrs, :src)
    lightbox_srcset = Keyword.get(attrs.img, :data_srcset)

    assigns =
      assigns
      |> assign(:attrs, attrs)
      |> assign(:lightbox_src, lightbox_src)
      |> assign(:lightbox_srcset, lightbox_srcset)

    ~H"""
    <%= if @opts[:lightbox] do %>
      <.lightbox src={@lightbox_src} srcset={@lightbox_srcset}>
        <.picture_tag src={@src} opts={@opts} attrs={@attrs} />
      </.lightbox>
    <% else %>
      <.picture_tag src={@src} opts={@opts} attrs={@attrs} />
    <% end %>
    """
  end

  defp picture_tag(%{src: src, attrs: attrs, opts: opts} = assigns) do
    figcaption? = Keyword.get(opts, :caption) && src.title && src.title != ""

    assigns =
      assigns
      |> assign(:figcaption?, figcaption?)
      |> assign(:noscript_alt, Keyword.get(attrs.opts, :alt, Map.get(src, :alt, "")))

    ~H"""
    <figure {@attrs.figure}>
      <picture {@attrs.picture}>
        <.mq_sources mqs={@attrs.mq_sources} />
        <.source_tags src={@src} attrs={@attrs} />
        <img {@attrs.img} />
        <.noscript_tag attrs={@attrs.noscript_img} alt={@noscript_alt} />
      </picture>
      <%= if @figcaption? do %>
        <.figcaption_tag caption={@src.title} />
      <% end %>
    </figure>
    """
  end

  defp mq_sources(assigns) do
    ~H"""
    <%= for {media, srcset} <- @mqs do %><source media={media} srcset={srcset} /><% end %>
    """
  end

  defp source_tags(%{src: %{formats: nil}, attrs: attrs} = assigns) do
    # if all source attrs are false (except type, which we don't care about)
    # drop the source tag
    if Enum.all?(Keyword.drop(attrs.source, [:type]), fn {_k, v} -> v == false end) do
      ~H||
    else
      ~H|<source {@attrs.source} />|
    end
  end

  defp source_tags(%{src: %{formats: formats}, attrs: attrs} = assigns) do
    # if all source attrs are false (except type, which we don't care about)
    # drop the source tag
    if Enum.all?(Keyword.drop(attrs.source, [:type]), fn {_k, v} -> v == false end) do
      ~H||
    else
      sizes_format = List.first(formats)
      assigns = assign(assigns, :sizes_format, sizes_format)
      # FIXME: only add one source for gifs for now -- sharp doesn't seem to handle
      # animated webps very well?
      if sizes_format == :gif do
        ~H"""
        <source {@attrs.source} />
        """
      else
        ~H"""
        <%= for format <- Enum.reverse(@src.formats) do %><%= if format == @sizes_format do %><source {@attrs.source} /><% else %><source {replace_attrs(@attrs.source, format)} /><% end %><% end %>
        """
      end
    end
  end

  defp figcaption_tag(assigns) do
    ~H"""
    <figcaption><%= Phoenix.HTML.raw(@caption) %></figcaption>
    """
  end

  defp noscript_tag(assigns) do
    ~H"""
    <noscript>
      <img alt={@alt} {@attrs} />
    </noscript>
    """
  end

  defp lightbox(assigns) do
    ~H"""
    <a href={@src} data-srcset={@srcset} data-lightbox={@src}>
      <%= render_slot(@inner_block) %>
    </a>
    """
  end

  defp replace_attrs(source_attrs, format) do
    Enum.map(source_attrs, fn
      {:data_srcset, v} -> {:data_srcset, suffix_srcs(v, ".#{format}")}
      {:srcset, v} -> {:srcset, suffix_srcs(v, ".#{format}")}
      {:type, _} -> {:type, "image/#{format}"}
      {k, v} -> {k, v}
    end)
  end

  defp suffix_srcs(false, _), do: false

  defp suffix_srcs(srcs, suffix),
    do: String.replace(srcs, [".jpg", ".jpeg", ".png", ".avif", ".gif"], suffix)

  defp add_alt(attrs, image_struct) do
    alt = Keyword.get(attrs.opts, :alt, Map.get(image_struct, :alt, "") || "")
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

  def add_original_type(attrs, %{path: path} = img) do
    case Brando.Images.Utils.image_type(path) do
      {:error, ext} ->
        raise """

        Unknown image type [#{ext}]

        #{inspect(attrs, pretty: true)}

        #{inspect(img, pretty: true)}

        """

      type ->
        Map.put(attrs, :type, type)
    end
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

  defp add_srcset(%{type: :svg} = attrs, _) do
    Map.put(attrs, :cropped_ratio, false)
  end

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
  defp srcset_placeholder?("svg"), do: true
  defp srcset_placeholder?("dominant_color"), do: true
  defp srcset_placeholder?(false), do: true
  defp srcset_placeholder?(_), do: false

  defp add_mq(%{lazyload: _} = attrs, image_struct) do
    case (Keyword.get(attrs.opts, :media_queries) &&
            get_mq(image_struct, attrs.opts[:media_queries], attrs.opts)) ||
           false do
      false ->
        attrs

      mqs ->
        put_in(attrs, [:mq_sources], mqs)
    end
  end

  defp add_src(%{type: :svg, lazyload: true} = attrs, image_struct) do
    placeholder = Keyword.get(attrs.opts, :placeholder, false)

    src = Utils.img_url(image_struct, :original, attrs.opts)

    fallback =
      case placeholder do
        :svg -> svg_fallback(image_struct, 0.05, attrs.opts)
        "svg" -> svg_fallback(image_struct, 0.05, attrs.opts)
        :dominant_color -> svg_fallback(image_struct, 0, attrs.opts)
        "dominant_color" -> svg_fallback(image_struct, 0, attrs.opts)
        false -> false
        _ -> Utils.img_url(image_struct, placeholder, attrs.opts)
      end

    attrs
    |> put_in([:img, :src], fallback)
    |> put_in([:img, :data_src], src)
    |> put_in([:noscript_img, :src], src)
    |> Map.put(:src, src)
  end

  defp add_src(%{type: :svg, lazyload: false} = attrs, image_struct) do
    src = Utils.img_url(image_struct, :original, attrs.opts)

    attrs
    |> put_in([:img, :src], src)
    |> put_in([:img, :data_src], false)
    |> put_in([:noscript_img, :src], src)
    |> Map.put(:src, src)
  end

  defp add_src(%{lazyload: true} = attrs, image_struct) do
    placeholder = Keyword.get(attrs.opts, :placeholder, false)

    key = Keyword.get(attrs.opts, :key) || :small
    src = Utils.img_url(image_struct, key, attrs.opts)

    fallback =
      case placeholder do
        :svg -> svg_fallback(image_struct, 0.05, attrs.opts)
        "svg" -> svg_fallback(image_struct, 0.05, attrs.opts)
        :dominant_color -> svg_fallback(image_struct, 0, attrs.opts)
        "dominant_color" -> svg_fallback(image_struct, 0, attrs.opts)
        false -> false
        _ -> Utils.img_url(image_struct, placeholder, attrs.opts)
      end

    attrs
    |> put_in([:img, :src], fallback)
    |> put_in([:img, :data_src], (placeholder == :micro && src) || fallback)
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
    |> Map.put(:src, src)
  end

  defp add_dominant_color(attrs, image_struct) do
    case Keyword.get(attrs.opts, :placeholder) do
      pl when pl in [:dominant_color, "dominant_color"] ->
        style = "background-color: #{image_struct.dominant_color || "transparent"}"

        attrs
        |> put_in([:picture, :style], style)
        |> put_in([:figure, :data_placeholder], "dominant_color")

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
    |> put_in([:figure, :data_orientation], orientation)
    |> put_in([:picture, :data_orientation], orientation)
  end

  defp add_dims(%{cropped_ratio: cropped_ratio} = attrs, image_struct) do
    img_width = Map.get(image_struct, :width)
    img_height = Map.get(image_struct, :height)

    width =
      case img_width do
        nil -> false
        width -> width
      end

    height =
      case img_height do
        nil -> false
        _ -> round(width / cropped_ratio)
      end

    orientation = Brando.Images.get_image_orientation(width, height)

    attrs
    |> put_in([:img, :width], width)
    |> put_in([:img, :height], height)
    |> put_in([:picture, :data_orientation], orientation)
  end

  defp add_moonwalk(attrs) do
    moonwalk = Keyword.get(attrs.opts, :moonwalk, false)
    put_in(attrs, [:figure, :data_moonwalk], moonwalk)
  end

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
  Get just the srcset
  """
  def get_srcset!(image_field, srcset, opts, placeholder \\ false) do
    {_, srcset} = get_srcset(image_field, srcset, opts, placeholder)
    srcset
  end

  @doc """
  Get srcset from image config
  """
  def get_srcset(image_field, cfg, opts, placeholder \\ false)
  def get_srcset(_, nil, _, _), do: {false, nil}

  def get_srcset(image_field, "default", opts, placeholder) do
    default_config = Brando.config(Brando.Images)[:default_config]
    get_srcset(image_field, default_config.srcset, opts, placeholder)
  end

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
    {:ok, %{cfg: cfg}} = {:ok, apply(mod, :__asset_opts__, [field])}

    if !Map.get(cfg, :srcset) do
      raise ArgumentError,
        message: "no `:srcset` key set in #{inspect(mod)}'s #{inspect(field)} image config"
    end

    {cropped_ratio, list} =
      case cfg.srcset do
        %{default: list} -> {check_cropped(cfg, :default), list}
        list when is_list(list) -> {false, list}
      end

    srcset_values =
      for {k, v} <- list do
        path =
          Utils.img_url(
            image_field,
            (placeholder not in [:svg, :dominant_color, "svg", "dominant_color"] && placeholder) ||
              k,
            opts
          )

        "#{path} #{v}"
      end

    {cropped_ratio, Enum.join(srcset_values, ", ")}
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
    {:ok, %{cfg: cfg}} = {:ok, apply(mod, :__asset_opts__, [field])}

    if !cfg.srcset do
      raise ArgumentError,
        message: "no `:srcset` key set in #{inspect(mod)}'s #{inspect(field)} image config"
    end

    if !Map.get(cfg.srcset, key) do
      raise ArgumentError,
        message:
          "no `#{inspect(key)}` key set in #{inspect(mod)}'s #{inspect(field)} srcset config"
    end

    # check if it is cropped
    cropped_ratio = check_cropped(cfg, key)

    srcset_values =
      for {k, v} <- Map.get(cfg.srcset, key) do
        path =
          Utils.img_url(
            image_field,
            (placeholder not in [:svg, :dominant_color, "svg", "dominant_color"] && placeholder) ||
              k,
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
            (placeholder not in [:svg, :dominant_color, "svg", "dominant_color"] && placeholder) ||
              k,
            opts
          )

        "#{path} #{v}"
      end

    {false, Enum.join(srcset_values, ", ")}
  end

  # a keyed srcset map, without a key. try to get default
  def get_srcset(image_field, %{default: srcset}, opts, placeholder) do
    srcset_values =
      for {k, v} <- srcset do
        path =
          Utils.img_url(
            image_field,
            (placeholder not in [:svg, :dominant_color, "svg", "dominant_color"] && placeholder) ||
              k,
            opts
          )

        "#{path} #{v}"
      end

    {false, Enum.join(srcset_values, ", ")}
  end

  def get_srcset(_, srcset, _, _) when is_map(srcset) do
    raise """
    Trying to get srcset from a keyed srcset with no key given and no `default` key in srcset

    #{inspect(srcset, pretty: true)}
    """
  end

  def get_srcset(image_field, :default, opts, placeholder) do
    default_config = Brando.config(Brando.Images)[:default_config]
    get_srcset(image_field, default_config.srcset, opts, placeholder)
  end

  def get_srcset(image_field, srcset, opts, placeholder) do
    srcset_values =
      for {k, v} <- srcset do
        path =
          Utils.img_url(
            image_field,
            (placeholder not in [:svg, :dominant_color, "svg", "dominant_color"] && placeholder) ||
              k,
            opts
          )

        "#{path} #{v}"
      end

    {false, Enum.join(srcset_values, ", ")}
  end

  defp check_cropped(%{sizes: sizes, srcset: srcset}, key) do
    cropped_srcset = Map.get(srcset, key)

    cfg_key_to_check =
      cropped_srcset
      |> List.last()
      |> elem(0)

    size = Map.get(sizes, cfg_key_to_check)

    if Map.get(size, "crop") do
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
