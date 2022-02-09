defmodule Brando.Villain.Parser do
  @moduledoc """
  Defines callbacks for the Villain.Parser behaviour.
  """

  @doc "Parses a comment"
  @callback comment(data :: map, opts :: map) :: binary

  @doc "Parses a header"
  @callback header(data :: map, opts :: map) :: binary

  @doc "Parses text/paragraphs"
  @callback text(data :: map, opts :: map) :: binary

  @doc "Parses video"
  @callback video(data :: map, opts :: map) :: binary

  @doc "Parses media"
  @callback media(data :: map, opts :: map) :: binary

  @doc "Parses map"
  @callback map(data :: map, opts :: map) :: binary

  @doc "Parses input (deprecated)"
  @callback input(data :: map, opts :: map) :: binary

  @doc "Parses gallery"
  @callback gallery(data :: map, opts :: map) :: binary

  @doc "Parses divider (deprecated)"
  @callback divider(data :: map, opts :: map) :: binary

  @doc "Parses list (deprecated)"
  @callback list(data :: map, opts :: map) :: binary

  @doc "Parses blockquote (deprecated)"
  @callback blockquote(data :: map, opts :: map) :: binary

  @doc "Parses datatables (deprecated)"
  @callback datatable(data :: map, opts :: map) :: binary

  @doc "Parses table"
  @callback table(data :: map, opts :: map) :: binary

  @doc "Parses markdown (deprecated)"
  @callback markdown(data :: map, opts :: map) :: binary

  @doc "Parses html"
  @callback html(data :: map, opts :: map) :: binary

  @doc "Parses svg"
  @callback svg(data :: map, opts :: map) :: binary

  @doc "Parses module"
  @callback module(data :: map, opts :: map) :: binary

  @doc "Parses datasource"
  @callback datasource(data :: map, opts :: map) :: binary

  @doc "Renders caption for picture block"
  @callback render_caption(data :: map) :: binary

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Brando.Villain.Parser
      use Phoenix.Component

      import Brando.HTML
      import Phoenix.HTML

      alias Brando.Cache
      alias Brando.Content
      alias Brando.Datasource
      alias Brando.Utils
      alias Brando.Villain

      alias Liquex.Context

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

      defoverridable render_caption: 1

      @doc """
      Convert header to HTML
      """
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
        "<#{header_size}#{classes}#{id}>" <> nl2br(text) <> "</#{header_size}>"
      end

      def header(%{text: text}, _), do: "<h1>" <> nl2br(text) <> "</h1>"
      defoverridable header: 2

      @doc """
      Value of an InputBlock.
      """
      def input(%{value: value}, _), do: value
      defoverridable input: 2

      @doc """
      Convert module to html.
      """
      def module(
            %{
              multi: true,
              module_id: id,
              entries: entries
            } = block,
            opts
          ) do
        base_context = opts.context
        modules = opts.modules

        {:ok, module} = Content.find_module(modules, id)

        content =
          entries
          |> Enum.with_index()
          |> Enum.map(fn {entry, index} ->
            vars = process_vars(entry.data.vars)
            refs = process_refs(entry.data.refs)

            forloop = %{
              "index" => index + 1,
              "index0" => index,
              "count" => Enum.count(entries)
            }

            context =
              base_context
              |> add_vars_to_context(vars)
              |> add_refs_to_context(refs)
              |> add_admin_to_context(opts)
              |> add_parser_to_context(__MODULE__)
              |> add_module_id_to_context(id)
              |> Context.assign("forloop", forloop)

            module.entry_template.code
            |> Villain.parse_and_render(context)
          end)
          |> Enum.join("\n")

        base_vars = process_vars(block.vars)
        base_refs = process_refs(block.refs)

        entries =
          Enum.map(entries, fn entry ->
            entry
            |> put_in([Access.key(:data), Access.key(:vars)], process_vars(entry.data.vars))
            |> put_in([Access.key(:data), Access.key(:refs)], process_refs(entry.data.refs))
          end)

        context =
          base_context
          |> add_vars_to_context(base_vars)
          |> add_refs_to_context(base_refs)
          |> add_admin_to_context(opts)
          |> add_parser_to_context(__MODULE__)
          |> add_module_id_to_context(id)
          |> Context.assign("entries", entries)
          |> Context.assign("content", content)

        module.code
        |> Villain.parse_and_render(context)
      end

      def module(%{module_id: id, refs: refs, vars: vars} = block, opts) do
        base_context = opts.context
        modules = opts.modules

        {:ok, module} = Content.find_module(modules, id)

        base_context = opts.context
        processed_vars = process_vars(vars)
        processed_refs = process_refs(refs)

        context =
          base_context
          |> add_vars_to_context(processed_vars)
          |> add_refs_to_context(processed_refs)
          |> add_admin_to_context(opts)
          |> add_parser_to_context(__MODULE__)
          |> add_module_id_to_context(id)

        module.code
        |> Villain.parse_and_render(context)
      end

      defoverridable module: 2

      def datasource(
            %{
              module: module,
              type: :list,
              query: query,
              code: code
            } = data,
            opts
          ) do
        arg = Map.get(data, :arg, nil)
        src_module_id = Map.get(data, :module_id, nil)
        src = (src_module_id && {:module, src_module_id}) || {:code, code}

        with {:ok, entries} <- Datasource.get_list(module, query, arg) do
          render_datasource_entries(src, entries, opts)
        end
      end

      def datasource(
            %{
              module: module,
              type: :selection,
              query: query,
              code: code,
              ids: ids
            } = data,
            opts
          ) do
        arg = Map.get(data, :arg, nil)
        src_module_id = Map.get(data, :module_id, nil)
        src = (src_module_id && {:module, src_module_id}) || {:code, code}

        with {:ok, entries} <- Datasource.get_selection(module, query, ids) do
          render_datasource_entries(src, entries, opts)
        end
      end

      def datasource(_, _), do: ""

      defoverridable datasource: 2

      @doc """
      Convert text to HTML through Markdown
      """
      def text(%{text: text} = params, _) do
        case Map.get(params, :type) do
          nil -> text
          "paragraph" -> text
          type -> "<div class=\"#{type}\">#{text}</div>"
        end
      end

      defoverridable text: 2

      @doc """
      Html -> html. Easy as pie.
      """
      def html(%{text: html}, _), do: html
      defoverridable html: 2

      @doc """
      Svg -> html. Easy as pie.
      """
      def svg(%{code: html}, _), do: html
      defoverridable svg: 2

      @doc """
      Markdown -> html
      """
      def markdown(%{text: markdown}, _) do
        Earmark.as_html!(markdown, %Earmark.Options{breaks: true})
      end

      defoverridable markdown: 2

      @doc """
      Convert GMaps url to iframe html
      """
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

      defoverridable map: 2

      @doc """
      Convert YouTube video to iframe html
      """
      def video(%{remote_id: remote_id, source: :youtube}, _) do
        params = "autoplay=1&controls=0&showinfo=0&rel=0"
        ~s(<div class="video-wrapper">
             <iframe width="420"
                     height="315"
                     src="//www.youtube.com/embed/#{remote_id}?#{params}"
                     frameborder="0"
                     allowfullscreen>
             </iframe>
           </div>)
      end

      def video(%{remote_id: remote_id, source: :vimeo}, _) do
        ~s(<div class="video-wrapper">
             <iframe src="//player.vimeo.com/video/#{remote_id}?dnt=1"
                     width="500"
                     height="281"
                     frameborder="0"
                     webkitallowfullscreen
                     mozallowfullscreen
                     allowfullscreen>
             </iframe>
           </div>)
      end

      # Convert file video to html
      def video(%{remote_id: src, source: :file} = data, _) do
        opts = [
          width: data.width,
          height: data.height,
          cover: :svg,
          autoplay: data.autoplay || nil,
          poster: data.poster || nil,
          preload: data.preload || true,
          opacity: data.opacity || 0.1
        ]

        %{video: src, opts: opts}
        |> video()
        |> Phoenix.LiveViewTest.rendered_to_string()
      end

      def video(_, _), do: ""

      defoverridable video: 2

      @doc """
      A media block, means that the user did not pick a media type -- so just return empty
      """
      def media(_, _), do: ""
      defoverridable media: 2

      @doc """
      Convert image to html, with caption and credits and optional link
      """
      def picture(%{url: ""}, _), do: ""

      def picture(data, _) do
        title = Map.get(data, :title, nil)
        credits = Map.get(data, :credits, nil)
        alt = Map.get(data, :alt, nil)
        width = Map.get(data, :width, nil)
        height = Map.get(data, :height, nil)
        orientation = (width > height && "landscape") || "portrait"
        lightbox = Map.get(data, :lightbox, nil)
        placeholder = Map.get(data, :placeholder, nil)
        moonwalk = Map.get(data, :moonwalk, false)
        lazyload = Map.get(data, :lazyload, false)
        default_srcset = Brando.config(Brando.Images)[:default_srcset]

        link = Map.get(data, :link) || ""
        img_class = Map.get(data, :img_class, "")
        picture_class = Map.get(data, :picture_class, "")
        srcset = Map.get(data, :srcset, nil)

        media_queries = Map.get(data, :media_queries)

        title = if title == "", do: nil, else: title
        credits = if credits == "", do: nil, else: credits
        srcset = if srcset == "", do: nil, else: srcset

        {rel, target} =
          if String.starts_with?(link, "/") or String.starts_with?(link, "#") do
            {"", ""}
          else
            {"nofollow noopener", "_blank"}
          end

        caption = render_caption(Map.merge(data, %{title: title, credits: credits}))
        media_queries = nil

        alt =
          cond do
            alt -> alt
            caption -> caption
            true -> ""
          end

        assigns = %{
          src: data,
          link: link,
          rel: rel,
          target: target,
          orientation: orientation,
          opts: [
            caption: caption,
            img_class: img_class,
            picture_class: picture_class,
            media_queries: media_queries,
            alt: alt,
            moonwalk: moonwalk,
            lazyload: lazyload,
            width: width,
            height: height,
            lightbox: lightbox,
            placeholder: placeholder,
            srcset: srcset || default_srcset,
            prefix: Brando.Utils.media_url()
          ]
        }

        assigns
        |> Brando.Villain.Parser.picture_tag()
        |> Phoenix.LiveViewTest.rendered_to_string()
      end

      defoverridable picture: 2

      @doc """
      Gallery.

      3 types:

        - slider
        - slideshow
        - gallery

      """
      def gallery(%{type: :slider, images: images} = data, _) do
        default_srcset = Brando.config(Brando.Images)[:default_srcset]

        items =
          Enum.map_join(images, "\n", fn img ->
            orientation = (img["width"] > img["height"] && "landscape") || "portrait"
            caption = img["title"] || nil

            assigns = %{
              src: img,
              orientation: orientation,
              caption: caption,
              opts: [
                key: :xlarge,
                caption: caption,
                alt: img["title"] || "Ill.",
                width: true,
                height: true,
                placeholder: :svg,
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
          Enum.map_join(images, "\n", fn img ->
            title = Map.get(img, :title, nil)
            credits = Map.get(img, :credits, nil)
            alt = Map.get(img, :alt, nil)
            width = Map.get(img, :width, nil)
            height = Map.get(img, :height, nil)
            placeholder = Map.get(data, :placeholder, :svg)

            placeholder =
              (is_binary(placeholder) && String.to_existing_atom(placeholder)) || placeholder

            orientation = (img.width > img.height && "landscape") || "portrait"
            caption = render_caption(Map.merge(img, %{title: title, credits: credits}))

            assigns = %{
              src: img,
              link: "",
              caption: caption,
              orientation: orientation,
              opts: [
                key: :xlarge,
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
          Enum.map_join(images, "\n", fn img ->
            title = Map.get(img, :title, nil)
            credits = Map.get(img, :credits, nil)
            alt = Map.get(img, :alt, nil)
            width = Map.get(img, :width, nil)
            height = Map.get(img, :height, nil)
            placeholder = Map.get(data, :placeholder, :svg)

            placeholder =
              (is_binary(placeholder) && String.to_existing_atom(placeholder)) || placeholder

            orientation = (img.width > img.height && "landscape") || "portrait"
            caption = render_caption(Map.merge(img, %{title: title, credits: credits}))

            assigns = %{
              src: img,
              link: "",
              caption: caption,
              orientation: orientation,
              opts: [
                key: :xlarge,
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
      def gallery(data, _), do: ""

      defoverridable gallery: 2

      @doc """
      List
      """
      def list(%{rows: rows} = data, _) do
        rows_html =
          Enum.map_join(rows, "\n", fn row ->
            class = (row[:class] && ~s( class="#{row.class}")) || ""
            value = row.value

            """
            <li#{class}>
              #{value}
            </li>
            """
          end)

        ul_id = (data.id && ~s( id="#{data.id}")) || ""
        ul_class = (data.class && ~s( class="#{data.class}")) || ""

        """
        <ul#{ul_id}#{ul_class}>
          #{rows_html}
        </ul>
        """
      end

      defoverridable list: 2

      @doc """
      Datatable
      """
      def datatable(%{rows: rows}, _) do
        rows_html =
          Enum.map_join(rows, "\n", fn row ->
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
          Enum.map_join(rows, "\n", fn row ->
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

        """
        <div class="data-table-wrapper">
          <table class="data-table">
            #{rows_html}
          </table>
        </div>
        """
      end

      defoverridable datatable: 2

      @doc """
      Table
      """
      def table(_, _) do
        # TODO
        ""
      end

      defoverridable table: 2

      @doc """
      Convert divider/hr to html
      """
      def divider(_, _), do: ~s(<hr>)
      defoverridable divider: 2

      @doc """
      Converts quote to html.
      """
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

      defoverridable blockquote: 2

      @doc """
      Strip comments
      """
      def comment(_, _), do: ""
      defoverridable comment: 2

      @doc """
      Convert container to html. Recursive parsing.
      """
      def container(%{blocks: blocks, palette_id: palette_id, target_id: target_id}, opts) do
        palettes = opts.palettes

        blocks_html =
          (blocks || [])
          |> Enum.reduce([], fn
            %{hidden: true}, acc -> acc
            %{marked_as_deleted: true}, acc -> acc
            d, acc -> [apply(__MODULE__, String.to_atom(d.type), [d.data, opts]) | acc]
          end)
          |> Enum.reverse()
          |> Enum.join("")

        target_id =
          (target_id && " id=\"#{target_id}\" data-scrollspy-trigger=\"##{target_id}\"") || ""

        case Content.find_palette(palettes, palette_id) do
          {:ok, palette} ->
            """
            <section b-section="#{palette.namespace}-#{palette.key}"#{target_id}>
              #{blocks_html}
            </section>
            """

          {:error, {:palette, :not_found, nil}} ->
            """
            <section b-section#{target_id}>
              #{blocks_html}
            </section>
            """
        end
      end

      defoverridable container: 2

      @doc """
      Timeline
      """
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

      defoverridable timeline: 2

      # ...
      defp process_vars(nil), do: %{}
      defp process_vars(vars), do: Enum.map(vars, &process_var(&1)) |> Enum.into(%{})

      defp process_var(
             %Brando.Content.Var.Image{
               key: key,
               label: _,
               type: _,
               value: %Ecto.Association.NotLoaded{}
             } = var
           ) do
        %{value: value} = Brando.repo().preload(var, [:value])
        {key, value}
      end

      defp process_var(%{key: key, label: _, type: _, value: value}), do: {key, value}

      defp process_refs(nil), do: %{}
      defp process_refs(refs), do: Enum.map(refs, &process_ref(&1)) |> Enum.into(%{})

      defp process_ref(%{name: ref_name} = ref_block), do: {ref_name, ref_block}

      defp add_vars_to_context(context, vars),
        do: Enum.reduce(vars, context, fn {k, v}, acc -> Context.assign(acc, k, v) end)

      defp add_refs_to_context(context, refs),
        do: Context.assign(context, :refs, refs)

      defp add_admin_to_context(context, opts) do
        if Map.get(opts, :brando_render_for_admin) do
          Context.assign(context, :brando_render_for_admin, true)
        else
          context
        end
      end

      defp add_parser_to_context(context, module),
        do: Context.assign(context, :brando_parser_module, module)

      defp add_module_id_to_context(context, module_id),
        do: Context.assign(context, :brando_module_id, module_id)

      defp render_datasource_entries({:code, code}, entries, opts) do
        base_context =
          (opts[:context] || Liquex.Context.new(%{}))
          |> add_parser_to_context(__MODULE__)

        context = Context.assign(base_context, "entries", entries)
        Villain.parse_and_render(code, context)
      end

      defp render_datasource_entries({:module, module_id}, entries, opts) do
        base_context =
          (opts[:context] || Liquex.Context.new(%{}))
          |> add_parser_to_context(__MODULE__)

        modules = opts.modules

        {:ok, module} = Content.find_module(modules, module_id)
        context = Context.assign(base_context, "entries", entries)
        Villain.parse_and_render(module.code, context)
      end
    end
  end

  use Phoenix.Component
  import Brando.HTML

  def picture_tag(assigns) do
    ~H"""
    <%= if @src.path do %>
      <div class="picture-wrapper" data-orientation={@orientation}>
        <%= if @link != "" do %>
          <.link url={@link} rel={@rel} target={@target}>
            <.picture
              src={@src}
              opts={@opts} />
          </.link>
        <% else %>
          <.picture
            src={@src}
            opts={@opts} />
        <% end %>
      </div>
    <% end %>
    """
  end

  def panner_item(assigns) do
    ~H"""
    <figure data-panner-item data-orientation={@orientation} data-moonwalk="panner">
      <.picture src={@src} opts={@opts} />
    </figure>
    """
  end
end
