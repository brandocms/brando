defmodule Brando.Villain.Parser do
  @moduledoc """
  Defines callbacks for the Villain.Parser behaviour.
  """

  @doc "Parses a comment"
  @callback comment(data :: map, opts :: map) :: iodata

  @doc "Parses a header"
  @callback header(data :: map, opts :: map) :: iodata

  @doc "Parses text/paragraphs"
  @callback text(data :: map, opts :: map) :: iodata

  @doc "Parses video"
  @callback video(data :: map, opts :: map) :: iodata

  @doc "Parses media"
  @callback media(data :: map, opts :: map) :: iodata

  @doc "Parses map"
  @callback map(data :: map, opts :: map) :: iodata

  @doc "Parses input (deprecated)"
  @callback input(data :: map, opts :: map) :: iodata

  @doc "Parses gallery"
  @callback gallery(data :: map, opts :: map) :: iodata

  @doc "Parses divider (deprecated)"
  @callback divider(data :: map, opts :: map) :: iodata

  @doc "Parses list (deprecated)"
  @callback list(data :: map, opts :: map) :: iodata

  @doc "Parses blockquote (deprecated)"
  @callback blockquote(data :: map, opts :: map) :: iodata

  @doc "Parses datatables (deprecated)"
  @callback datatable(data :: map, opts :: map) :: iodata

  @doc "Parses table"
  @callback table(data :: map, opts :: map) :: iodata

  @doc "Parses markdown (deprecated)"
  @callback markdown(data :: map, opts :: map) :: iodata

  @doc "Parses html"
  @callback html(data :: map, opts :: map) :: iodata

  @doc "Parses svg"
  @callback svg(data :: map, opts :: map) :: iodata

  @doc "Parses module"
  @callback module(data :: map, opts :: map) :: iodata

  @doc "Parses datasource"
  @callback datasource(data :: map, opts :: map) :: iodata

  @doc "Renders caption for picture block"
  @callback render_caption(data :: map) :: iodata

  @doc "Default options passed to <.video> component for :file type"
  @callback video_file_options(data :: map) :: list

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Brando.Villain.Parser

      def render_caption(map), do: Brando.Villain.Parser.render_caption(map)
      defoverridable render_caption: 1

      def video_file_options(data), do: Brando.Villain.Parser.video_file_options(data)
      defoverridable video_file_options: 1

      def header(data, opts), do: Brando.Villain.Parser.header(data, opts)
      defoverridable header: 2

      def input(%{value: value}, _), do: value
      defoverridable input: 2

      def module(data, opts), do: Brando.Villain.Parser.module(data, opts)
      defoverridable module: 2

      def datasource(_, _) do
        require Logger

        Logger.error("==> parser: datasource/2 is deprecated. Use module with datasource instead.")

        ""
      end

      defoverridable datasource: 2

      def text(data, opts), do: Brando.Villain.Parser.text(data, opts)
      defoverridable text: 2

      def html(data, opts), do: Brando.Villain.Parser.html(data, opts)
      defoverridable html: 2

      def svg(data, opts), do: Brando.Villain.Parser.svg(data, opts)
      defoverridable svg: 2

      def markdown(data, opts), do: Brando.Villain.Parser.markdown(data, opts)
      defoverridable markdown: 2

      def map(data, opts), do: Brando.Villain.Parser.map(data, opts)
      defoverridable map: 2

      def video(data, opts), do: Brando.Villain.Parser.video(data, opts)
      defoverridable video: 2

      @doc """
      A media block, means that the user did not pick a media type -- so just return empty
      """
      def media(data, opts), do: Brando.Villain.Parser.media(data, opts)
      defoverridable media: 2

      @doc """
      Convert image to html, with caption and credits and optional link
      """
      def picture(data, opts), do: Brando.Villain.Parser.picture(data, opts)
      defoverridable picture: 2

      @doc """
      Gallery.

      3 types:

        - slider
        - slideshow
        - gallery

      """
      def gallery(data, opts), do: Brando.Villain.Parser.gallery(data, opts)
      defoverridable gallery: 2

      @doc """
      List
      """
      def list(data, opts), do: Brando.Villain.Parser.list(data, opts)
      defoverridable list: 2

      @doc """
      Datatable
      """
      def datatable(data, opts), do: Brando.Villain.Parser.datatable(data, opts)
      defoverridable datatable: 2

      @doc """
      Table
      """

      def table(data, opts), do: Brando.Villain.Parser.table(data, opts)
      defoverridable table: 2

      @doc """
      Convert divider/hr to html
      """
      def divider(data, opts), do: Brando.Villain.Parser.divider(data, opts)
      defoverridable divider: 2

      @doc """
      Converts quote to html.
      """
      def blockquote(data, opts), do: Brando.Villain.Parser.blockquote(data, opts)
      defoverridable blockquote: 2

      @doc """
      Strip comments
      """
      def comment(data, opts), do: Brando.Villain.Parser.comment(data, opts)
      defoverridable comment: 2

      @doc """
      Convert container to html. Recursive parsing.
      """
      def container(data, opts), do: Brando.Villain.Parser.container(data, opts)
      defoverridable container: 2

      @doc """
      Timeline
      """
      def timeline(data, opts), do: Brando.Villain.Parser.timeline(data, opts)
      defoverridable timeline: 2

      def fragment(data, opts), do: Brando.Villain.Parser.fragment(data, opts)
      defoverridable fragment: 2
    end
  end

  use Phoenix.Component
  import Brando.HTML

  alias Brando.Content
  alias Brando.Utils
  alias Brando.Villain.TemplateAdapter

  @doc """
  Returns the template adapter module for a given template type.
  """
  def adapter_for(:liquid), do: TemplateAdapter.Liquex
  def adapter_for(:heex), do: TemplateAdapter.Heex
  def adapter_for(nil), do: TemplateAdapter.Liquex

  def header(%{text: nil}, _), do: ""

  def header(%{text: text, level: level, anchor: anchor}, _) do
    h = header(%{text: text, level: level}, [])
    ~s(<a name="#{anchor}"></a>#{h})
  end

  def header(%{text: text, level: level} = data, _) do
    classes =
      if Map.get(data, :class, nil) do
        ~s( class="#{Map.get(data, :class)}")
      else
        ""
      end

    id =
      if Map.get(data, :id, nil) do
        ~s( id="#{Map.get(data, :id)}")
      else
        ""
      end

    header_size = "h#{level}"

    if link = Map.get(data, :link) do
      ~s(<a href="#{link}"><#{header_size}#{classes}#{id}>#{nl2br(text)}</#{header_size}></a>)
    else
      ["<", header_size, classes, id, ">", nl2br(text), "</", header_size, ">"]
    end
  end

  def header(%{text: text}, _), do: ["<h1>", nl2br(text), "</h1>"]

  def module(%{active: false} = block, opts) do
    # we might want to annotate disabled modules
    maybe_annotate("", block.uid, opts)
  end

  def module(%{multi: true, module_id: id, children: children} = block, opts) do
    modules = opts.modules
    skip_children? = Map.get(opts, :skip_children, false)

    {:ok, module} = Content.find_module(modules, id)
    adapter = adapter_for(module.type)
    opts = Map.put(opts, :parser_module, __MODULE__)

    content =
      if skip_children? do
        "[$ content $]"
        |> annotate_children(block.uid)
      else
        children
        |> Enum.with_index()
        |> Enum.map(fn
          {%{active: false}, _} ->
            ""

          {%{marked_as_deleted: true}, _} ->
            ""

          {child_block, index} ->
            {:ok, child_module} = Content.find_module(modules, child_block.module_id)

            vars = process_vars(child_block.vars)
            refs = process_refs(child_block.refs)

            forloop = %{
              "index" => index + 1,
              "index0" => index,
              "count" => Enum.count(children)
            }

            adapter.render_child_module(child_module, child_block, vars, refs, forloop, id, opts)
            |> maybe_annotate(child_block.uid, opts)
        end)
        |> Enum.intersperse("\n")
        |> annotate_children(block.uid)
      end

    base_vars = process_vars(block.vars)
    base_refs = process_refs(block.refs)

    children =
      case children do
        nil -> []
        %Ecto.Association.NotLoaded{} -> []
        _ -> children
      end

    children =
      Enum.map(children, fn entry ->
        entry
        |> put_in([Access.key(:vars)], process_vars(entry.vars))
        |> put_in([Access.key(:refs)], process_refs(entry.refs))
      end)

    adapter.render_multi_module(module, block, base_vars, base_refs, children, IO.iodata_to_binary(content), opts)
    |> maybe_annotate(block.uid, opts)
    |> maybe_format(opts)
  end

  def module(%{module_id: id} = block, opts) do
    modules = opts.modules

    case Content.find_module(modules, id) do
      {:ok, module} ->
        processed_vars = process_vars(block.vars)
        processed_refs = process_refs(block.refs)
        adapter = adapter_for(module.type)
        opts = Map.put(opts, :parser_module, __MODULE__)

        adapter.render_module(module, block, processed_vars, processed_refs, opts)
        |> maybe_annotate(block.uid, opts)
        |> maybe_format(opts)

      {:error, {:module, :not_found, module_id}} ->
        """
        <div class="module-not-found">
          <p>Module not found: #{module_id}</p>
        </div>
        """
    end
  end

  def text(%{text: text} = params, _) do
    case Map.get(params, :type) do
      nil -> text
      "paragraph" -> text
      type -> "<div class=\"#{type}\">#{text}</div>"
    end
  end

  def html(%{text: html}, _), do: html
  def svg(%{code: html}, _), do: html

  def markdown(%{text: markdown}, _) do
    Earmark.as_html!(markdown, %Earmark.Options{breaks: true})
  end

  def map(%{embed_url: embed_url, source: :gmaps}, _) do
    ~s(<div class="map-wrapper">
         <iframe width="420"
                 height="315"
                 src="#{embed_url}"
                 frameborder="0"
                 allowfullscreen>
         </iframe>
       </div>)
  end

  # Extract dimension data with defaults
  defp extract_video_dimensions(data, default_width, default_height) do
    width = Map.get(data, :width, default_width)
    height = Map.get(data, :height, default_height)
    orientation = (width > height && "landscape") || "portrait"

    %{width: width, height: height, orientation: orientation}
  end

  # Calculate aspect ratio with fallback
  defp calculate_aspect_ratio(width, height) do
    if height > 0 && width > 0 do
      height / width
    else
      # Default 16:9 aspect ratio
      0.5625
    end
  end

  # Render iframe video with common wrapper
  defp render_iframe_video(width, height, orientation, aspect_ratio, src, extra_attrs \\ false) do
    # For YouTube
    youtube_template =
      ~s(<div class="video-wrapper video-embed" data-orientation="#{orientation}" style="--aspect-ratio: #{aspect_ratio}">
         <iframe width="#{width}"
                 height="#{height}"
                 src="#{src}"
                 frameborder="0"
                 allowfullscreen>
         </iframe>
       </div>)

    # For Vimeo
    vimeo_template =
      ~s(<div class="video-wrapper video-embed" data-orientation="#{orientation}" style="--aspect-ratio: #{aspect_ratio}">
         <iframe src="#{src}"
                 width="#{width}"
                 height="#{height}"
                 frameborder="0"
                 webkitallowfullscreen
                 mozallowfullscreen
                 allowfullscreen>
         </iframe>
       </div>)

    if extra_attrs, do: vimeo_template, else: youtube_template
  end

  def video(%{remote_id: remote_id, type: :youtube, autoplay: autoplay} = data, _) do
    video_fields = extract_video_dimensions(data, 420, 315)
    aspect_ratio = calculate_aspect_ratio(video_fields.width, video_fields.height)
    params = "autoplay=#{(autoplay && 1) || 0}&controls=0&showinfo=0&rel=0"

    render_iframe_video(
      video_fields.width,
      video_fields.height,
      video_fields.orientation,
      aspect_ratio,
      "//www.youtube.com/embed/#{remote_id}?#{params}"
    )
  end

  def video(%{remote_id: remote_id, type: :vimeo} = data, _) do
    video_fields = extract_video_dimensions(data, 500, 281)

    # Ensure values are integers
    width = (is_integer(video_fields.width) && video_fields.width) || String.to_integer(video_fields.width)
    height = (is_integer(video_fields.height) && video_fields.height) || String.to_integer(video_fields.height)

    aspect_ratio = calculate_aspect_ratio(width, height)

    render_iframe_video(
      width,
      height,
      video_fields.orientation,
      aspect_ratio,
      "//player.vimeo.com/video/#{remote_id}?dnt=1",
      # Enable additional fullscreen attributes for Vimeo
      true
    )
  end

  def video(%{source_url: src, type: :external_file} = data, _) do
    assigns = %{
      video: src,
      opts: video_file_options(data),
      cover_image: Map.get(data, :cover_image)
    }

    assigns
    |> Brando.Villain.Parser.video_tag()
    |> Phoenix.LiveViewTest.rendered_to_string()
  end

  # Convert file video to html
  def video(%{remote_id: src, type: :upload} = data, _) do
    assigns = %{
      video: src,
      opts: video_file_options(data),
      cover_image: Map.get(data, :cover_image)
    }

    assigns
    |> Brando.Villain.Parser.video_tag()
    |> Phoenix.LiveViewTest.rendered_to_string()
  end

  def video(_, _), do: ""
  def media(_, _), do: ""

  def picture(%{url: ""}, _), do: ""
  def picture(nil, _), do: ""

  def picture(data, _) do
    # Extract data fields with defaults
    fields = extract_picture_fields(data)

    # Process text fields
    fields = process_picture_text_fields(fields)

    # Determine link attributes
    {rel, target} = get_link_attributes(fields.link)

    # Get caption and determine alt text
    caption = render_caption(Map.merge(data, %{title: fields.title, credits: fields.credits}))
    alt = get_alt_text(fields.alt, caption)

    # Build assigns for the template
    assigns = build_picture_assigns(data, fields, rel, target, caption, alt)

    # Render picture
    assigns
    |> Brando.Villain.Parser.picture_tag()
    |> Phoenix.LiveViewTest.rendered_to_string()
  end

  # Extract raw fields with default values from data
  defp extract_picture_fields(data) do
    %{
      title: Map.get(data, :title, nil),
      credits: Map.get(data, :credits, nil),
      alt: Map.get(data, :alt, nil),
      width: Map.get(data, :width, nil),
      height: Map.get(data, :height, nil),
      lightbox: Map.get(data, :lightbox, nil),
      placeholder: Map.get(data, :placeholder, nil),
      moonwalk: Map.get(data, :moonwalk, false),
      lazyload: Map.get(data, :lazyload, false),
      link: Map.get(data, :link) || "",
      img_class: Map.get(data, :img_class, ""),
      picture_class: Map.get(data, :picture_class, ""),
      srcset: Map.get(data, :srcset, nil)
    }
  end

  # Process text fields (handle empty strings)
  defp process_picture_text_fields(fields) do
    %{
      fields
      | title: if(fields.title == "", do: nil, else: fields.title),
        credits: if(fields.credits == "", do: nil, else: fields.credits),
        srcset: if(fields.srcset == "", do: nil, else: fields.srcset)
    }
  end

  # Determine link attributes based on link URL
  defp get_link_attributes(link) do
    if String.starts_with?(link, "/") or String.starts_with?(link, "#") do
      {"", ""}
    else
      {"nofollow noopener", "_blank"}
    end
  end

  # Determine alt text with proper fallbacks
  defp get_alt_text(alt, caption) do
    cond do
      alt != "" -> alt
      caption != "" -> caption
      true -> ""
    end
  end

  # Build assigns map for the template
  defp build_picture_assigns(data, fields, rel, target, caption, alt) do
    orientation = (fields.width > fields.height && "landscape") || "portrait"
    default_srcset = Brando.config(Brando.Images)[:default_srcset]

    %{
      src: data,
      link: fields.link,
      rel: rel,
      target: target,
      orientation: orientation,
      opts: [
        caption: caption,
        img_class: fields.img_class,
        picture_class: fields.picture_class,
        media_queries: nil,
        alt: alt,
        moonwalk: fields.moonwalk,
        lazyload: fields.lazyload,
        width: fields.width,
        height: fields.height,
        lightbox: fields.lightbox,
        placeholder: fields.placeholder,
        srcset: fields.srcset || default_srcset,
        sizes: "auto",
        prefix: Brando.Utils.media_url()
      ]
    }
  end

  def gallery(%{type: :slider, images: images} = data, _) do
    default_srcset = Brando.config(Brando.Images)[:default_srcset]

    items =
      images
      |> Enum.map(fn img ->
        title = Map.get(img, :title, nil)
        credits = Map.get(img, :credits, nil)
        alt = Map.get(img, :alt, nil)
        placeholder = Map.get(data, :placeholder, :svg)

        placeholder =
          (is_binary(placeholder) && String.to_existing_atom(placeholder)) || placeholder

        orientation = (img.width > img.height && "landscape") || "portrait"
        caption = render_caption(Map.merge(img, %{title: title, credits: credits}))

        alt = if alt, do: alt, else: ""

        assigns = %{
          src: img,
          link: "",
          caption: caption,
          orientation: orientation,
          opts: [
            key: :largest,
            caption: caption,
            alt: alt,
            width: true,
            height: true,
            placeholder: placeholder,
            sizes: "auto",
            srcset: default_srcset,
            lazyload: true,
            lightbox: data.lightbox || false,
            prefix: Utils.media_url()
          ]
        }

        assigns
        |> Brando.Villain.Parser.panner_item()
        |> Phoenix.LiveViewTest.rendered_to_string()
      end)
      |> Enum.intersperse("\n")

    """
    <div data-panner-container>
      <div class="inner">
        <section class="items" data-panner>
          #{items}
        </section>
      </div>
    </div>
    """
  end

  def gallery(%{type: :slideshow, images: images} = data, _) do
    class = Map.get(data, :class, "")
    default_srcset = Brando.config(Brando.Images)[:default_srcset]

    items =
      images
      |> Enum.map(fn img ->
        title = Map.get(img, :title, nil)
        credits = Map.get(img, :credits, nil)
        alt = Map.get(img, :alt, nil)
        placeholder = Map.get(data, :placeholder, :svg)

        placeholder =
          (is_binary(placeholder) && String.to_existing_atom(placeholder)) || placeholder

        orientation = (img.width > img.height && "landscape") || "portrait"
        caption = render_caption(Map.merge(img, %{title: title, credits: credits}))

        alt = if alt, do: alt, else: ""

        assigns = %{
          src: img,
          link: "",
          caption: caption,
          orientation: orientation,
          opts: [
            key: :largest,
            caption: caption,
            alt: alt,
            width: true,
            height: true,
            placeholder: placeholder,
            sizes: "auto",
            srcset: default_srcset,
            lazyload: true,
            lightbox: data.lightbox || false,
            prefix: Utils.media_url()
          ]
        }

        assigns
        |> Brando.Villain.Parser.picture_tag()
        |> Phoenix.LiveViewTest.rendered_to_string()
      end)
      |> Enum.intersperse("\n")

    """
    <div data-slideshow="#{class}">
      #{items}
    </div>
    """
  end

  def gallery(%{type: :gallery, images: images} = data, _) do
    class = Map.get(data, :class, "")
    default_srcset = Brando.config(Brando.Images)[:default_srcset]

    items =
      images
      |> Enum.map(fn img ->
        title = Map.get(img, :title, nil)
        credits = Map.get(img, :credits, nil)
        alt = Map.get(img, :alt, nil)
        placeholder = Map.get(data, :placeholder, :svg)

        placeholder =
          (is_binary(placeholder) && String.to_existing_atom(placeholder)) || placeholder

        orientation = (img.width > img.height && "landscape") || "portrait"
        caption = render_caption(Map.merge(img, %{title: title, credits: credits}))

        alt = if alt, do: alt, else: ""

        assigns = %{
          src: img,
          link: "",
          caption: caption,
          orientation: orientation,
          opts: [
            key: :largest,
            caption: caption,
            alt: alt,
            width: true,
            height: true,
            placeholder: placeholder,
            sizes: "auto",
            srcset: default_srcset,
            lazyload: true,
            lightbox: data.lightbox || false,
            prefix: Utils.media_url()
          ]
        }

        assigns
        |> Brando.Villain.Parser.picture_tag()
        |> Phoenix.LiveViewTest.rendered_to_string()
      end)
      |> Enum.intersperse("\n")

    """
    <div data-gallery="#{class}">
      <div class="inner">
        <section data-gallery-items>
          #{items}
        </section>
      </div>
    </div>
    """
  end

  # empty gallery
  def gallery(_data, _), do: ""

  def list(%{rows: rows} = data, _) do
    rows_html =
      rows
      |> Enum.map(fn row ->
        class = (row[:class] && ~s( class="#{row.class}")) || ""
        value = row.value

        """
        <li#{class}>
          #{value}
        </li>
        """
      end)
      |> Enum.intersperse("\n")

    ul_id = (data.id && ~s( id="#{data.id}")) || ""
    ul_class = (data.class && ~s( class="#{data.class}")) || ""

    """
    <ul#{ul_id}#{ul_class}>
      #{rows_html}
    </ul>
    """
  end

  def datatable(%{rows: rows}, _) do
    rows_html =
      rows
      |> Enum.map(fn row ->
        """
        <tr>
          <td class="key">
            #{row.key}
          </td>
          <td class="value">
            #{row.value}
          </td>
        </tr>
        """
      end)
      |> Enum.intersperse("\n")

    """
    <div class="data-table-wrapper">
      <table class="data-table">
        #{rows_html}
      </table>
    </div>
    """
  end

  @doc """
  Datatable (Legacy)
  """
  def datatable(rows, _) when is_list(rows) do
    rows_html =
      rows
      |> Enum.map(fn row ->
        """
        <tr>
          <td class="key">
            #{row.key}
          </td>
          <td class="value">
            #{row.value}
          </td>
        </tr>
        """
      end)
      |> Enum.intersperse("\n")

    """
    <div class="data-table-wrapper">
      <table class="data-table">
        #{rows_html}
      </table>
    </div>
    """
  end

  def table(_, _) do
    # TODO
    ""
  end

  def divider(_, _), do: ~s(<hr>)

  def blockquote(%{text: text, cite: cite}, _)
      when byte_size(cite) > 0 do
    text_html = Earmark.as_html!(text)

    """
    <blockquote>
      #{text_html}
      <p class="cite">
        — <cite>#{cite}</cite>
      </p>
    </blockquote>
    """
  end

  def blockquote(%{text: text}, _) do
    text_html = Earmark.as_html!(text)

    """
    <blockquote>
      #{text_html}
    </blockquote>
    """
  end

  def comment(_, _), do: ""

  def container(%{active: false, children: children} = block, opts) do
    skip_children? = Map.get(opts, :skip_children, false)

    children_html =
      case skip_children? do
        true ->
          "[$ content $]"
          |> annotate_children(block.uid)

        false ->
          ""

        :force_render ->
          (children || [])
          |> Enum.reduce([], fn
            %{active: false}, acc -> acc
            %{marked_as_deleted: true}, acc -> acc
            d, acc -> [apply(__MODULE__, d.type, [d, opts]) | acc]
          end)
          |> Enum.reverse()
          |> annotate_children(block.uid)
      end

    # we might want to annotate disabled containers
    maybe_annotate(children_html, block.uid, opts)
  end

  def container(
        %{children: children, palette_id: palette_id, anchor: target_id, container_id: nil} =
          block,
        opts
      ) do
    palettes = opts.palettes
    skip_children? = Map.get(opts, :skip_children, false)

    children_html =
      if skip_children? === true do
        "[$ content $]"
        |> annotate_children(block.uid)
      else
        (children || [])
        |> Enum.reduce([], fn
          %{active: false}, acc -> acc
          %{marked_as_deleted: true}, acc -> acc
          d, acc -> [apply(__MODULE__, d.type, [d, opts]) | acc]
        end)
        |> Enum.reverse()
        |> annotate_children(block.uid)
      end

    target_id =
      (target_id && " id=\"#{target_id}\" data-scrollspy-trigger=\"##{target_id}\"") || ""

    case Content.find_palette(palettes, palette_id) do
      {:ok, palette} ->
        colors = palette.colors |> Enum.map(&"--#{&1.key}: #{&1.hex_value}") |> Enum.intersperse(";")
        palette_vars = " style=\"#{colors}\""

        """
        <section b-section="#{palette.namespace}-#{palette.key}"#{target_id}#{palette_vars}>
          #{children_html}
        </section>
        """
        |> maybe_annotate(block.uid, opts)
        |> maybe_format(opts)

      {:error, {:palette, :not_found, nil}} ->
        """
        <section b-section#{target_id}>
          #{children_html}
        </section>
        """
        |> maybe_annotate(block.uid, opts)
        |> maybe_format(opts)
    end
  end

  def container(
        %{
          children: children,
          palette_id: _palette_id,
          anchor: _target_id,
          container_id: container_id
        } =
          block,
        opts
      ) do
    containers = opts.containers
    # palettes = opts.palettes
    skip_children? = Map.get(opts, :skip_children, false)
    {:ok, container} = Content.find_container(containers, container_id)

    children_html =
      if skip_children? === true do
        annotate_children("[$ content $]", block.uid)
      else
        (children || [])
        |> Enum.reduce([], fn
          %{active: false}, acc -> acc
          %{marked_as_deleted: true}, acc -> acc
          d, acc -> [apply(__MODULE__, d.type, [d, opts]) | acc]
        end)
        |> Enum.reverse()
        |> annotate_children(block.uid)
      end

    adapter = adapter_for(container.type)

    adapter.render_container(container, IO.iodata_to_binary(children_html), block, opts)
    |> maybe_annotate(block.uid, opts)
    |> maybe_format(opts)
  end

  def timeline(items, _) do
    timeline_html =
      for item <- items do
        ~s(
            <li class="villain-timeline-item">
              <div class="villain-timeline-item-date">
                <div class="villain-timeline-item-date-inner">
                  #{Map.get(item, :caption)}
                </div>
              </div>
              <div class="villain-timeline-item-content">
                <div class="villain-timeline-item-content-inner">
                  #{Map.get(item, :text)}
                </div>
              </div>
            </li>
            )
      end

    ~s(<ul class="villain-timeline">#{timeline_html}</ul>)
  end

  def fragment(%{fragment_id: nil}, _),
    do: "<!-- fragment not embedded. fragment_id = nil -->"

  def fragment(%{fragment_id: id}, opts) do
    fragments = opts.fragments
    {:ok, fragment} = Brando.Pages.find_fragment(fragments, id)

    case fragment.status do
      :published -> fragment.rendered_blocks
      _ -> "<!-- fragment##{id} not embedded. status != :published -->"
    end
  end

  def render_caption(%{title: nil, credits: nil}), do: ""
  def render_caption(%{title: "", credits: nil}), do: ""
  def render_caption(%{title: nil, credits: ""}), do: ""
  def render_caption(%{title: "", credits: ""}), do: ""

  def render_caption(%{title: title, credits: nil}),
    do: "#{title}"

  def render_caption(%{title: nil, credits: credits}),
    do: "#{credits}"

  def render_caption(%{title: title, credits: credits}),
    do: "#{title} — #{credits}"

  def video_file_options(data) do
    # Extract config values with consistent access patterns
    has_play_button = Map.get(data, :play_button, false)
    autoplay_setting = Map.get(data, :autoplay)

    # Determine play button display
    play_button = get_play_button_setting(has_play_button, autoplay_setting)

    # Determine if autoplay should be enabled
    autoplay = autoplay_setting not in [nil, false]

    # Build the options list
    [
      width: Map.get(data, :width),
      height: Map.get(data, :height),
      cover: :svg,
      autoplay: autoplay,
      poster: Map.get(data, :poster),
      preload: get_preload_setting(data),
      opacity: Map.get(data, :opacity, 0.1),
      controls: Map.get(data, :controls, false),
      caption: Map.get(data, :title, false),
      play_button: play_button
    ]
  end

  # Helper function for determining play button setting
  defp get_play_button_setting(has_play_button, autoplay_setting) do
    if has_play_button && autoplay_setting == false do
      Brando.config(:video_play_button_text) || true
    else
      false
    end
  end

  # Helper function for determining preload setting
  defp get_preload_setting(data) do
    preload = Map.get(data, :preload)
    if is_nil(preload), do: true, else: preload
  end

  def replace_fragments(html) do
    html = IO.iodata_to_binary(html)
    fragments = Regex.scan(~r/{% fragment (\w+) (\w+) (\w+) %}/, html)

    if fragments != [] do
      Enum.reduce(fragments, html, fn [_, parent_key, key, language], updated_html ->
        rendered_fragment =
          parent_key
          |> Brando.Pages.render_fragment(key, language)
          |> Phoenix.HTML.safe_to_string()

        String.replace(updated_html, "{% fragment #{parent_key} #{key} #{language} %}", rendered_fragment)
      end)
    else
      html
    end
  end

  def picture_tag(assigns) do
    ~H"""
    <%= if Map.get(@src, :path) do %>
      <div class="picture-wrapper" data-orientation={@orientation}>
        <%= if @link != "" do %>
          <.link href={@link} rel={@rel} target={@target}>
            <.picture src={@src} opts={@opts} />
          </.link>
        <% else %>
          <.picture src={@src} opts={@opts} />
        <% end %>
      </div>
    <% end %>
    """
  end

  def video_tag(%{cover_image: cover_image} = assigns) when not is_nil(cover_image) do
    ~H"""
    <.video video={@video} opts={@opts}>
      <:cover>
        <.picture
          src={@cover_image}
          opts={[
            lazyload: true,
            sizes: "auto",
            srcset: :default,
            placeholder: :dominant_color,
            prefix: Brando.Utils.media_url()
          ]}
        />
      </:cover>
    </.video>
    """
  end

  def video_tag(assigns) do
    ~H"""
    <.video video={@video} opts={@opts} />
    """
  end

  def panner_item(assigns) do
    ~H"""
    <figure data-panner-item data-orientation={@orientation} data-moonwalk="panner">
      <.picture src={@src} opts={@opts} />
    </figure>
    """
  end

  def add_meta_to_entries(entries, block) do
    # do we have any meta?
    Enum.map(entries, fn entry ->
      entry_schema = entry.__struct__
      entry_id = entry.id
      meta = get_meta(block.identifier_metas || [], entry_schema, entry_id)
      %{entry: entry, meta: meta}
    end)
  end

  defp get_meta(identifier_metas, schema, id) do
    identifier_metas
    |> Enum.find(fn {existing_id, _meta} -> "#{inspect(schema)}_#{id}" == existing_id end)
    |> case do
      nil -> nil
      {_, meta} -> meta
    end
  end

  # ...
  defp process_vars(nil), do: %{}
  defp process_vars(%Ecto.Association.NotLoaded{}), do: []
  defp process_vars(vars), do: Enum.map(vars, &process_var(&1)) |> Enum.into(%{})

  defp process_var(
         %Brando.Content.Var{
           type: :link,
           key: key,
           label: _,
           identifier_id: identifier_id,
           identifier: %Ecto.Association.NotLoaded{}
         } = var
       )
       when not is_nil(identifier_id) do
    preloaded_var = Brando.Repo.preload(var, [:identifier])
    {key, preloaded_var}
  end

  defp process_var(
         %Brando.Content.Var{
           type: :image,
           key: key,
           label: _,
           image: %Ecto.Association.NotLoaded{}
         } = var
       ) do
    %{image: image} = Brando.Repo.preload(var, [:image])
    {key, image}
  end

  defp process_var(%Brando.Content.Var{
         type: :image,
         key: key,
         label: _,
         image: image
       }) do
    {key, image}
  end

  defp process_var(
         %Brando.Content.Var{
           type: :file,
           key: key,
           label: _,
           file: %Ecto.Association.NotLoaded{}
         } = var
       ) do
    %{file: file} = Brando.Repo.preload(var, [:file])
    {key, file}
  end

  defp process_var(%Brando.Content.Var{
         type: :file,
         key: key,
         label: _,
         file: file
       }) do
    {key, file}
  end

  defp process_var(%{key: key, label: _, type: :boolean, value_boolean: value_boolean}),
    do: {key, value_boolean}

  defp process_var(%{key: key, label: _, type: :link} = link),
    do: {key, link}

  defp process_var(%{key: key, label: _, type: _, value: value}), do: {key, value}

  defp process_refs(nil), do: %{}

  defp process_refs(refs), do: Map.new(refs, &process_ref(&1))

  defp process_ref(%{name: ref_name} = ref_block) do
    # Build the processed ref by combining data with referenced entities
    processed_ref =
      ref_block
      |> merge_ref_associations()
      |> Map.put(:original_ref, ref_block)

    {ref_name, processed_ref}
  end

  defp merge_ref_associations(%{data: %{type: "picture"}} = ref) do
    merged_data =
      case {Map.get(ref, :image), Map.get(ref, :image_id)} do
        {nil, nil} ->
          # No image association and no image_id, return the block data as-is
          ref.data.data

        {nil, image_id} when is_integer(image_id) ->
          # No image association but we have image_id, load the image
          case Brando.Images.get_image(image_id) do
            {:ok, image} ->
              override_data = Map.from_struct(ref.data.data || %{})

              override_attrs =
                Map.take(override_data, [
                  :title,
                  :credits,
                  :alt,
                  :picture_class,
                  :img_class,
                  :link,
                  :srcset,
                  :media_queries,
                  :lazyload,
                  :moonwalk,
                  :placeholder,
                  :fetchpriority
                ])

              Brando.Content.OverrideResolver.merge_overrides(image, override_attrs)

            _ ->
              ref.data.data
          end

        {image, _} ->
          # We have an image, so we should return the image data with overrides
          # from the block data (like custom title, credits, alt)
          override_data = Map.from_struct(ref.data.data || %{})

          override_attrs =
            Map.take(override_data, [
              :title,
              :credits,
              :alt,
              :picture_class,
              :img_class,
              :link,
              :srcset,
              :media_queries,
              :lazyload,
              :moonwalk,
              :placeholder,
              :fetchpriority
            ])

          # Merge into the image struct, nil values = use image default
          Brando.Content.OverrideResolver.merge_overrides(image, override_attrs)
      end

    # Return the ref structure with merged data, including active status
    %{
      data: %{data: merged_data, type: "picture"},
      name: ref.name,
      description: ref.description,
      active: Map.get(ref, :active, true),
      collapsed: Map.get(ref, :collapsed, false)
    }
  end

  defp merge_ref_associations(%{data: %{type: "video"}} = ref) do
    merged_data =
      case Map.get(ref, :video) do
        nil ->
          # No video association, return the block data as-is
          ref.data.data

        video ->
          # We have a video, so we should return the video data with overrides
          # from the block data
          override_data = Map.from_struct(ref.data.data || %{})

          override_attrs =
            Map.take(override_data, [
              :title,
              :poster,
              :autoplay,
              :opacity,
              :preload,
              :play_button,
              :controls,
              :cover,
              :aspect_ratio,
              :cover_image
            ])

          # Merge into the video struct, nil values = use video default
          Brando.Content.OverrideResolver.merge_overrides(video, override_attrs)
      end

    # Return the ref structure with merged data, including active status
    %{
      data: %{data: merged_data, type: "video"},
      name: ref.name,
      description: ref.description,
      active: Map.get(ref, :active, true),
      collapsed: Map.get(ref, :collapsed, false)
    }
  end

  defp merge_ref_associations(%{data: %{type: "gallery"}} = ref) do
    gallery =
      ref
      |> Map.get(:gallery)
      |> resolve_gallery_assoc(Map.get(ref, :gallery_id))

    {merged_data, merged_gallery} =
      case gallery do
        nil ->
          {ref.data.data, nil}

        %Brando.Galleries.Gallery{} = loaded_gallery ->
          # For galleries, expose the gallery association with override data
          override_data = Map.from_struct(ref.data.data || %{})

          # Apply caption overrides to gallery objects
          # TODO: Consider caching this merge operation for large galleries with many objects
          updated_gallery = apply_gallery_caption_overrides(loaded_gallery, override_data)

          # Return the block data with the updated gallery association
          {
            struct(ref.data.data.__struct__, Map.put(override_data, :gallery, updated_gallery)),
            updated_gallery
          }

        _ ->
          {ref.data.data, nil}
      end

    # Return the ref structure with merged data, including active status
    %{
      data: %{data: merged_data, type: "gallery"},
      gallery: merged_gallery,
      name: ref.name,
      description: ref.description,
      active: Map.get(ref, :active, true),
      collapsed: Map.get(ref, :collapsed, false)
    }
  end

  # Handle all other ref types (text, html, svg, etc.)
  defp merge_ref_associations(%{data: %{type: _type} = data} = ref) do
    # Return the ref structure with data, including active status
    %{
      data: data,
      name: ref.name,
      description: ref.description,
      active: Map.get(ref, :active, true),
      collapsed: Map.get(ref, :collapsed, false)
    }
  end

  defp merge_ref_associations(ref) do
    # Fallback for refs without proper data structure, including active status
    %{
      data: Map.get(ref, :data, %{}),
      name: Map.get(ref, :name),
      description: Map.get(ref, :description),
      active: Map.get(ref, :active, true),
      collapsed: Map.get(ref, :collapsed, false)
    }
  end

  defp resolve_gallery_assoc(%Ecto.Association.NotLoaded{}, gallery_id), do: fetch_gallery_assoc(gallery_id)
  defp resolve_gallery_assoc(nil, _gallery_id), do: nil
  defp resolve_gallery_assoc(gallery, _gallery_id), do: gallery

  defp fetch_gallery_assoc(nil), do: nil

  defp fetch_gallery_assoc(gallery_id) do
    case Brando.Repo.get(Brando.Galleries.Gallery, gallery_id) do
      nil ->
        nil

      gallery ->
        Brando.Repo.preload(gallery, gallery_objects: [:image, video: [:thumbnail]])
    end
  end

  defp apply_gallery_caption_overrides(gallery, override_data) do
    gallery_object_overrides = Map.get(override_data, :gallery_object_overrides, [])

    overrides_map =
      Enum.reduce(gallery_object_overrides, %{}, fn override, acc ->
        case override_object_id(override) do
          nil -> acc
          object_id -> Map.put(acc, object_id, override)
        end
      end)

    updated_gallery_objects =
      Enum.map(gallery.gallery_objects || [], fn gallery_object ->
        image = get_loaded_assoc(gallery_object, :image)
        video = get_loaded_assoc(gallery_object, :video)

        media_id =
          cond do
            image -> to_string(image.id)
            video -> to_string(video.id)
            true -> nil
          end

        object_override = Map.get(overrides_map, media_id)

        gallery_object =
          gallery_object
          |> maybe_put_loaded_assoc(:image, image)
          |> maybe_put_loaded_assoc(:video, video)

        cond do
          image && object_override ->
            %{gallery_object | image: apply_caption_overrides(image, object_override)}

          video && object_override ->
            updated_video =
              video
              |> apply_caption_overrides(object_override)
              |> apply_playback_overrides(object_override)

            %{gallery_object | video: updated_video}

          true ->
            gallery_object
        end
      end)

    %{gallery | gallery_objects: updated_gallery_objects}
  end

  defp get_loaded_assoc(gallery_object, :image) do
    image = Map.get(gallery_object, :image)
    image_id = Map.get(gallery_object, :image_id)

    cond do
      match?(%Brando.Images.Image{}, image) && stale_gallery_image?(image, image_id) ->
        fetch_gallery_image(image_id, image)

      match?(%Brando.Images.Image{}, image) ->
        image

      match?(%Ecto.Association.NotLoaded{}, image) && not is_nil(image_id) ->
        fetch_gallery_image(image_id)

      true ->
        nil
    end
  end

  defp get_loaded_assoc(gallery_object, :video) do
    with %Ecto.Association.NotLoaded{} <- Map.get(gallery_object, :video),
         video_id when not is_nil(video_id) <- Map.get(gallery_object, :video_id),
         {:ok, video} <- Brando.Videos.get_video(video_id) do
      video
    else
      %Brando.Videos.Video{} = video -> video
      _ -> nil
    end
  end

  defp maybe_put_loaded_assoc(gallery_object, _assoc, nil), do: gallery_object
  defp maybe_put_loaded_assoc(gallery_object, assoc, loaded), do: Map.put(gallery_object, assoc, loaded)

  defp stale_gallery_image?(%Brando.Images.Image{id: loaded_id, sizes: sizes}, image_id) do
    id_mismatch? = not is_nil(image_id) and to_string(loaded_id) != to_string(image_id)
    empty_sizes? = is_map(sizes) and map_size(sizes) == 0
    id_mismatch? || empty_sizes?
  end

  defp fetch_gallery_image(image_id, fallback \\ nil)
  defp fetch_gallery_image(nil, fallback), do: fallback

  defp fetch_gallery_image(image_id, fallback) do
    case Brando.Images.get_image(image_id) do
      {:ok, image} -> image
      _ -> fallback
    end
  end

  defp override_object_id(%Ecto.Changeset{} = override) do
    Ecto.Changeset.get_field(override, :object_id)
  end

  defp override_object_id(%{object_id: object_id}) do
    object_id
  end

  defp override_object_id(_), do: nil

  defp apply_caption_overrides(media_object, %Ecto.Changeset{} = override) do
    media_object
    |> maybe_apply_override(
      :title,
      Ecto.Changeset.get_field(override, :title),
      Ecto.Changeset.get_field(override, :use_default_title)
    )
    |> maybe_apply_override(
      :credits,
      Ecto.Changeset.get_field(override, :credits),
      Ecto.Changeset.get_field(override, :use_default_credits)
    )
    |> maybe_apply_override(
      :alt,
      Ecto.Changeset.get_field(override, :alt),
      Ecto.Changeset.get_field(override, :use_default_alt)
    )
  end

  defp apply_caption_overrides(media_object, override) do
    media_object
    |> maybe_apply_override(:title, override.title, override.use_default_title)
    |> maybe_apply_override(:credits, override.credits, override.use_default_credits)
    |> maybe_apply_override(:alt, override.alt, override.use_default_alt)
  end

  defp maybe_apply_override(media_object, field, value, use_default) do
    cond do
      # Legacy: explicit use_default flag
      use_default == true ->
        media_object

      # New convention: nil use_default + nil value = use default
      is_nil(use_default) and is_nil(value) ->
        media_object

      # Explicit override
      is_binary(value) ->
        Map.put(media_object, field, value)

      # Boolean override (for video playback fields)
      is_boolean(value) ->
        Map.put(media_object, field, value)

      # Fallback
      true ->
        media_object
    end
  end

  defp apply_playback_overrides(video, %Ecto.Changeset{} = override) do
    Enum.reduce(~w(autoplay loop muted controls preload)a, video, fn field, acc ->
      value = Ecto.Changeset.get_field(override, field)
      use_default = Ecto.Changeset.get_field(override, :"use_default_#{field}")
      maybe_apply_override(acc, field, value, use_default)
    end)
  end

  defp apply_playback_overrides(video, override) do
    Enum.reduce(~w(autoplay loop muted controls preload)a, video, fn field, acc ->
      value = Map.get(override, field)
      use_default = Map.get(override, :"use_default_#{field}")
      maybe_apply_override(acc, field, value, use_default)
    end)
  end

  def maybe_annotate(code, uid, %{annotate_blocks: true}) do
    ["<!-- [+:B<", uid, ">] -->\n  ", code, "\n<!-- [-:B<", uid, ">] -->\n"]
  end

  def maybe_annotate(code, _, _), do: code

  def annotate_children(code, uid) do
    ["<!-- [+:C<", uid, ">] -->\n  ", code, "\n<!-- [-:C<", uid, ">] -->\n"]
  end

  def maybe_format(html, %{format_html: true}) do
    html = IO.iodata_to_binary(html)

    try do
      Phoenix.LiveView.HTMLFormatter.format(html, [])
    rescue
      e ->
        require Logger

        Logger.error("""

        ==> Error formatting HTML.
        Pre-formatted HTML below:

        #{html}")

        """)

        reraise e, __STACKTRACE__
    end
  end

  def maybe_format(html, _), do: html
end
