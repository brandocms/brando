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

  @doc "Parses image"
  @callback image(data :: map, opts :: map) :: binary

  @doc "Parses input"
  @callback input(data :: map, opts :: map) :: binary

  @doc "Parses slideshow"
  @callback slideshow(data :: map, opts :: map) :: binary

  @doc "Parses gallery"
  @callback gallery(data :: map, opts :: map) :: binary

  @doc "Parses divider"
  @callback divider(data :: map, opts :: map) :: binary

  @doc "Parses list"
  @callback list(data :: map, opts :: map) :: binary

  @doc "Parses blockquote"
  @callback blockquote(data :: map, opts :: map) :: binary

  @doc "Parses columns"
  @callback columns(data :: map, opts :: map) :: binary

  @doc "Parses datatables"
  @callback datatable(data :: map, opts :: map) :: binary

  @doc "Parses markdown"
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

      import Brando.HTML
      import Phoenix.HTML

      alias Brando.Cache
      alias Brando.Datasource
      alias Brando.Villain

      alias Liquex.Context

      def render_caption(%{title: nil, credits: nil}), do: ""
      def render_caption(%{title: "", credits: nil}), do: ""
      def render_caption(%{title: nil, credits: ""}), do: ""
      def render_caption(%{title: "", credits: ""}), do: ""

      def render_caption(%{title: title, credits: nil}),
        do: "<figcaption>#{title}</figcaption>"

      def render_caption(%{title: nil, credits: credits}),
        do: "<figcaption>#{credits}</figcaption>"

      def render_caption(%{title: title, credits: credits}),
        do: "<figcaption>#{title} — #{credits}</figcaption>"

      defoverridable render_caption: 1

      @doc """
      Convert header to HTML
      """
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

        {:ok, module} = Villain.find_module(modules, id)

        content =
          Enum.map(Enum.with_index(entries), fn {%{refs: refs, vars: vars}, index} ->
            # add vars to context
            vars = process_vars(vars)

            forloop = %{
              "index" => index + 1,
              "index0" => index,
              "count" => Enum.count(entries)
            }

            context =
              base_context
              |> add_vars_to_context(vars)
              |> Context.assign("forloop", forloop)

            module.code
            |> render_refs(refs, id)
            |> Villain.parse_and_render(context)
          end)
          |> Enum.join("\n")

        context =
          base_context
          |> Context.assign("entries", entries)
          |> Context.assign("content", content)

        Villain.parse_and_render(module.wrapper, context)
      end

      def module(%{module_id: id, refs: refs} = block, opts) do
        base_context = opts.context
        modules = opts.modules

        {:ok, module} = Villain.find_module(modules, id)

        vars = Map.get(block, :vars)
        base_context = opts.context
        vars = process_vars(vars)

        context = add_vars_to_context(base_context, vars)

        module.code
        |> render_refs(refs, id)
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
      def map(%{embed_url: embed_url, source: "gmaps"}, _) do
        ~s(<div class="map-wrapper">
             <iframe width="420"
                     height="315"
                     src="https:#{embed_url}"
                     frameborder="0"
                     allowfullscreen>
             </iframe>
           </div>)
      end

      defoverridable map: 2

      @doc """
      Convert YouTube video to iframe html
      """
      def video(%{remote_id: remote_id, source: "youtube"}, _) do
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

      def video(%{remote_id: remote_id, source: "vimeo"}, _) do
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
      def video(%{remote_id: src, source: "file"} = data, _) do
        video_tag(src,
          width: data.width,
          height: data.height,
          cover: :svg,
          autoplay: data.autoplay || nil,
          poster: data.poster || nil,
          preload: data.preload || true,
          opacity: data.opacity || 0.1
        )
        |> safe_to_string()
      end

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
        data = Brando.Utils.coerce_struct(data, Brando.Images.Image)
        title = Map.get(data, :title, nil)
        credits = Map.get(data, :credits, nil)
        alt = Map.get(data, :alt, nil)
        width = Map.get(data, :width, nil)
        height = Map.get(data, :height, nil)
        orientation = (width > height && "landscape") || "portrait"
        lightbox = Map.get(data, :lightbox, nil)
        default_srcset = Brando.config(Brando.Images)[:default_srcset]

        link = Map.get(data, :link) || ""
        img_class = Map.get(data, :img_class, "")
        picture_class = Map.get(data, :picture_class, "")
        srcset = Map.get(data, :srcset, "")

        media_queries = Map.get(data, :media_queries, "")

        title = if title == "", do: nil, else: title
        credits = if credits == "", do: nil, else: credits

        {link_open, link_close} =
          if link != "" do
            {rel, target} =
              if String.starts_with?(link, "/") or String.starts_with?(link, "#") do
                {"", ""}
              else
                {~s( rel="nofollow noopener"), ~s( target="_blank")}
              end

            {~s(<a href="#{link}" #{rel}#{target}>), ~s(</a>)}
          else
            {"", ""}
          end

        caption = render_caption(Map.merge(data, %{title: title, credits: credits}))

        srcset =
          if srcset == "",
            do: default_srcset,
            else: Code.string_to_quoted!(srcset, existing_atoms_only: true)

        media_queries =
          if media_queries != "",
            do: Code.string_to_quoted!(media_queries, existing_atoms_only: true),
            else: nil

        alt =
          cond do
            alt -> alt
            caption -> caption
            true -> ""
          end

        ptag =
          picture_tag(data,
            img_class: img_class,
            picture_class: picture_class,
            media_queries: media_queries,
            alt: alt,
            width: true,
            height: true,
            lightbox: lightbox,
            placeholder: :svg,
            lazyload: true,
            sizes: "auto",
            srcset: srcset,
            cache: :timestamp
          )
          |> safe_to_string

        """
        <div class="picture-wrapper" data-orientation="#{orientation}">
          #{link_open}
          #{ptag}
          #{link_close}
          #{caption}
        </div>
        """
      end

      defoverridable picture: 2

      @doc """
      Convert image to html, with caption and credits and optional link
      """
      def image(data, _) do
        title = Map.get(data, :title, "")
        credits = Map.get(data, :credits, "")
        link = Map.get(data, :link, "")
        class = Map.get(data, :class, "")

        {link_open, link_close} =
          if link != "" do
            {~s(<a href="#{data.link}" title="#{title}">), ~s(</a>)}
          else
            {"", ""}
          end

        title = if title == "", do: nil, else: title

        caption =
          if title do
            """
            <p class="small photo-caption"><span class="arrow-se">&searr;</span> #{title}</p>
            """
          else
            ""
          end

        srcset = [
          {"small", "700w"},
          {"medium", "1000w"},
          {"large", "1400w"},
          {"xlarge", "1900w"}
        ]

        itag =
          img_tag(data, :xlarge,
            srcset: srcset,
            alt: "#{title}/#{credits}",
            class: class
          )
          |> safe_to_string

        """
        <div class="img-wrapper">
          #{link_open}
          #{itag}
          #{link_close}
          #{caption}
        </div>
        """
      end

      defoverridable image: 2

      @doc """
      Slideshow
      """
      def slideshow(%{images: images} = data, _) do
        default_srcset = Brando.config(Brando.Images)[:default_srcset]

        items =
          Enum.map_join(images, "\n", fn img ->
            orientation = (img["width"] > img["height"] && "landscape") || "portrait"
            caption = img["title"] || nil

            ptag =
              picture_tag(img,
                key: :xlarge,
                alt: img["title"] || "Ill.",
                width: true,
                height: true,
                placeholder: :svg,
                sizes: "auto",
                srcset: default_srcset,
                lazyload: true,
                lightbox: data.lightbox || false
              )
              |> safe_to_string

            """
            <figure data-panner-item data-orientation="#{orientation}" data-moonwalk="panner">
              #{ptag}
              <figcaption>#{caption}</figcaption>
            </figure>
            """
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

      defoverridable slideshow: 2

      @doc """
      Gallery
      """
      def gallery(%{images: images} = data, _) do
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

            ptag =
              picture_tag(img,
                key: :xlarge,
                alt: alt,
                width: true,
                height: true,
                placeholder: placeholder,
                sizes: "auto",
                srcset: default_srcset,
                lazyload: true,
                lightbox: data.lightbox || false
              )
              |> safe_to_string

            """
            <div class="picture-wrapper" data-orientation="#{orientation}">
              #{ptag}
              #{caption}
            </div>
            """
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
            class = (row.class && ~s( class="#{row.class}")) || ""
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
      Convert columns to html. Recursive parsing.
      """
      def columns(cols, opts) do
        col_html =
          for col <- cols do
            c =
              Enum.reduce(col["data"], [], fn d, acc ->
                [apply(__MODULE__, String.to_atom(d["type"]), [d["data"], opts]) | acc]
              end)

            class =
              case col["class"] do
                "six" -> "col-md-6"
                other -> other
              end

            ~s(<div class="#{class}">#{Enum.reverse(c)}</div>)
          end

        ~s(<div class="row">#{col_html}</div>)
      end

      @doc """
      Convert container to html. Recursive parsing.
      """
      def container(%{blocks: blocks, class: class, wrapper: wrapper}, opts) do
        blocks_html =
          blocks
          |> Enum.reduce([], fn d, acc ->
            [apply(__MODULE__, String.to_atom(d["type"]), [d["data"], opts]) | acc]
          end)
          |> Enum.reverse()
          |> Enum.join("")

        wrapper = (is_binary(wrapper) && String.length(wrapper) > 0 && wrapper) || nil

        if wrapper do
          String.replace(wrapper, "{{ content }}", blocks_html)
        else
          """
          <section b-section="#{class}">
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

      defp process_var({name, %{"label" => _, "type" => _, "value" => value}}), do: {name, value}

      defp add_vars_to_context(context, vars),
        do: Enum.reduce(vars, context, fn {k, v}, acc -> Context.assign(acc, k, v) end)

      defp render_datasource_entries({:code, code}, entries, opts) do
        base_context = opts.context
        context = Context.assign(base_context, "entries", entries)
        Villain.parse_and_render(code, context)
      end

      defp render_datasource_entries({:module, module_id}, entries, opts) do
        base_context = opts.context
        modules = opts.modules

        {:ok, module} = Villain.find_module(modules, module_id)
        context = Context.assign(base_context, "entries", entries)
        Villain.parse_and_render(module.code, context)
      end

      defp render_refs(module_code, refs, id) do
        Regex.replace(~r/%{(\w+)}/, module_code, fn _, match ->
          refs
          |> Enum.find(&(&1.name == match))
          |> render_ref(id, match)
        end)
      end

      defp render_ref(nil, id, match), do: "<!-- REF #{match} missing // module: #{id}. -->"
      defp render_ref(%{hidden: true}, _id, _match), do: "<!-- h -->"
      defp render_ref(%{deleted: true}, _id, _match), do: "<!-- d -->"

      defp render_ref(ref, _id, _match) do
        block = ref.data
        apply(__MODULE__, String.to_atom(block.type), [block.data, []])
      end
    end
  end
end
