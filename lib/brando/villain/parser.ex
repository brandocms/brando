defmodule Brando.Villain.Parser do
  @moduledoc """
  Defines callbacks for the Villain.Parser behaviour.
  """

  @doc "Parses a comment"
  @callback comment(data :: %{String.t() => any}, opts :: Keyword.t()) :: String.t()

  @doc "Parses a header"
  @callback header(data :: %{String.t() => any}, opts :: Keyword.t()) :: String.t()

  @doc "Parses text/paragraphs"
  @callback text(data :: %{String.t() => any}, opts :: Keyword.t()) :: String.t()

  @doc "Parses video"
  @callback video(data :: %{String.t() => any}, opts :: Keyword.t()) :: String.t()

  @doc "Parses map"
  @callback map(data :: %{String.t() => any}, opts :: Keyword.t()) :: String.t()

  @doc "Parses image"
  @callback image(data :: %{String.t() => any}, opts :: Keyword.t()) :: String.t()

  @doc "Parses slideshow"
  @callback slideshow(data :: %{String.t() => any}, opts :: Keyword.t()) :: String.t()

  @doc "Parses divider"
  @callback divider(data :: %{String.t() => any}, opts :: Keyword.t()) :: String.t()

  @doc "Parses list"
  @callback list(data :: %{String.t() => any}, opts :: Keyword.t()) :: String.t()

  @doc "Parses blockquote"
  @callback blockquote(data :: %{String.t() => any}, opts :: Keyword.t()) :: String.t()

  @doc "Parses columns"
  @callback columns(data :: %{String.t() => any}, opts :: Keyword.t()) :: String.t()

  @doc "Parses datatables"
  @callback datatable(data :: %{String.t() => any}, opts :: Keyword.t()) :: String.t()

  @doc "Parses markdown"
  @callback markdown(data :: %{String.t() => any}, opts :: Keyword.t()) :: String.t()

  @doc "Parses html"
  @callback html(data :: %{String.t() => any}, opts :: Keyword.t()) :: String.t()

  @doc "Parses svg"
  @callback svg(data :: %{String.t() => any}, opts :: Keyword.t()) :: String.t()

  @doc "Parses template"
  @callback template(data :: %{String.t() => any}, opts :: Keyword.t()) :: String.t()

  @doc "Parses datasource"
  @callback datasource(data :: %{String.t() => any}, opts :: Keyword.t()) :: String.t()

  defmacro __using__(_) do
    quote do
      @behaviour Brando.Villain.Parser

      import Brando.HTML
      import Phoenix.HTML

      alias Brando.Cache
      alias Brando.Datasource
      alias Brando.Lexer
      alias Brando.Villain

      @doc """
      Convert header to HTML
      """
      def header(%{"text" => text, "level" => level, "anchor" => anchor}, _) do
        h = header(%{"text" => text, "level" => level}, [])
        ~s(<a name="#{anchor}"></a>#{h})
      end

      def header(%{"text" => text, "level" => level} = data, _) do
        classes =
          if Map.get(data, "class", nil) do
            ~s( class="#{Map.get(data, "class")}")
          else
            ""
          end

        id =
          if Map.get(data, "id", nil) do
            ~s( id="#{Map.get(data, "id")}")
          else
            ""
          end

        header_size = "h#{level}"
        "<#{header_size}#{classes}#{id}>" <> nl2br(text) <> "</#{header_size}>"
      end

      def header(%{"text" => text}, _), do: "<h1>" <> nl2br(text) <> "</h1>"
      defoverridable header: 2

      @doc """
      Convert template to html.
      """
      def template(
            %{
              "multi" => true,
              "id" => id,
              "entries" => entries
            } = block,
            opts
          ) do
        {:ok, template} =
          case Keyword.get(opts, :cache_templates) do
            true ->
              Brando.Villain.get_cached_template(id)

            _ ->
              Brando.Villain.get_template(id)
          end

        # multi template
        {:ok, template} = Brando.Villain.get_template(id)

        base_context = opts[:context]

        content =
          Enum.map(Enum.with_index(entries), fn {%{"refs" => refs, "vars" => vars}, index} ->
            # add vars to context
            vars = process_vars(vars)

            forloop = %{
              "index" => index + 1,
              "index0" => index,
              "count" => Enum.count(entries)
            }

            context =
              base_context
              |> Lexer.Context.assign(vars)
              |> Lexer.Context.assign("forloop", forloop)

            template.code
            |> render_refs(refs, id)
            |> Lexer.parse_and_render(context)
          end)
          |> Enum.join("\n")

        context =
          base_context
          |> Lexer.Context.assign("entries", entries)
          |> Lexer.Context.assign("content", content)

        Lexer.parse_and_render(template.wrapper, context)
      end

      def template(%{"id" => id, "refs" => refs} = block, opts) do
        {:ok, template} =
          case Keyword.get(opts, :cache_templates) do
            true ->
              Brando.Villain.get_cached_template(id)

            _ ->
              Brando.Villain.get_template(id)
          end

        vars = Map.get(block, "vars")
        base_context = opts[:context]

        vars = process_vars(vars)

        context =
          base_context
          |> Lexer.Context.assign(vars)

        template.code
        |> render_refs(refs, id)
        |> Lexer.parse_and_render(context)
      end

      defoverridable template: 2

      def datasource(
            %{
              "module" => module,
              "type" => "many",
              "query" => query,
              "template" => template_id
            } = data,
            _
          ) do
        arg = Map.get(data, "arg", nil)

        with {:ok, entries} <- Datasource.get_many(module, query, arg),
             {:ok, template} <- Villain.get_template(template_id) do
          render_datasource_entries(template, entries)
        end
      end

      def datasource(
            %{
              "module" => module,
              "type" => "selection",
              "query" => query,
              "ids" => ids,
              "template" => template_id
            } = data,
            _
          ) do
        arg = Map.get(data, "arg", nil)

        with {:ok, entries} <- Datasource.get_selection(module, query, ids),
             {:ok, template} <- Villain.get_template(template_id) do
          render_datasource_entries(template, entries)
        end
      end

      defoverridable datasource: 2

      @doc """
      Convert text to HTML through Markdown
      """
      def text(%{"text" => text} = params, _) do
        text =
          case Map.get(params, "type") do
            nil -> text
            "paragraph" -> text
            type -> "<div class=\"#{type}\">#{text}</div>"
          end

        Earmark.as_html!(text, %Earmark.Options{breaks: true})
      end

      defoverridable text: 2

      @doc """
      Html -> html. Easy as pie.
      """
      def html(%{"text" => html}, _), do: html
      defoverridable html: 2

      @doc """
      Svg -> html. Easy as pie.
      """
      def svg(%{"code" => html}, _), do: html
      defoverridable svg: 2

      @doc """
      Markdown -> html
      """
      def markdown(%{"text" => markdown}, _) do
        Earmark.as_html!(markdown, %Earmark.Options{breaks: true})
      end

      defoverridable markdown: 2

      @doc """
      Convert GMaps url to iframe html
      """
      def map(%{"embed_url" => embed_url, "source" => "gmaps"}, _) do
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
      def video(%{"remote_id" => remote_id, "source" => "youtube"}, _) do
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

      def video(%{"remote_id" => remote_id, "source" => "vimeo"}, _) do
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
      def video(%{"remote_id" => src, "source" => "file"} = data, _) do
        video_tag(src, %{
          width: data["width"],
          height: data["height"],
          cover: :svg,
          poster: (data["poster"] && data["poster"]) || nil,
          preload: true,
          opacity: 0.1
        })
        |> safe_to_string()
      end

      defoverridable video: 2

      @doc """
      Convert image to html, with caption and credits and optional link
      """
      def picture(data, _) do
        title = Map.get(data, "title", "")
        credits = Map.get(data, "credits", "")
        alt = Map.get(data, "alt", nil)
        width = Map.get(data, "width", nil)
        height = Map.get(data, "height", nil)
        orientation = (width > height && "landscape") || "portrait"
        lightbox = Map.get(data, "lightbox", nil)

        link = Map.get(data, "link") || ""
        img_class = Map.get(data, "img_class", "")
        picture_class = Map.get(data, "picture_class", "")
        srcset = Map.get(data, "srcset", "")
        media_queries = Map.get(data, "media_queries", "")

        {link_open, link_close} =
          if link != "" do
            {rel, target} =
              if String.starts_with?(link, "/") or String.starts_with?(link, "#") do
                {"", ""}
              else
                {~s( rel="nofollow noopener"), ~s( target="_blank")}
              end

            {~s(<a href="#{link}" title="#{title}"#{rel}#{target}>), ~s(</a>)}
          else
            {"", ""}
          end

        title = if title == "", do: nil, else: title
        credits = if credits == "", do: nil, else: credits
        caption = if title == "", do: "", else: "<figcaption>#{title}</figcaption>"

        srcset =
          if srcset != "",
            do: Code.string_to_quoted!(srcset, existing_atoms_only: true),
            else: nil

        media_queries =
          if media_queries != "",
            do: Code.string_to_quoted!(media_queries, existing_atoms_only: true),
            else: nil

        alt =
          cond do
            alt ->
              alt

            title && credits ->
              "#{title} by #{credits}"

            title ->
              title

            credits ->
              "by #{credits}"

            true ->
              "Ill."
          end

        ptag =
          picture_tag(data,
            key: :xlarge,
            img_class: img_class,
            picture_class: picture_class,
            media_queries: media_queries,
            alt: alt,
            width: true,
            height: true,
            lightbox: lightbox,
            placeholder: :svg,
            lazyload: true,
            srcset: srcset
            # cache: img.updated_at,
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
        title = Map.get(data, "title", "")
        credits = Map.get(data, "credits", "")
        link = Map.get(data, "link", "")
        class = Map.get(data, "class", "")

        {link_open, link_close} =
          if link != "" do
            {~s(<a href="#{data["link"]}" title="#{title}">), ~s(</a>)}
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
      def slideshow(%{"images" => images} = data, _) do
        items =
          Enum.map_join(images, "\n", fn img ->
            orientation = (img["width"] > img["height"] && "landscape") || "portrait"
            caption = (img["title"] && img["title"]) || nil

            ptag =
              picture_tag(img,
                key: :xlarge,
                alt: img["title"] || "Ill.",
                width: true,
                height: true,
                placeholder: :svg,
                lazyload: true,
                lightbox: data["lightbox"] || false
              )
              |> safe_to_string

            """
            <figure data-panner-item data-orientation="#{orientation}" data-moonwalk="panner">
              #{ptag}
              <figcaption><p>#{caption}</p></figcaption>
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
      List
      """
      def list(%{"rows" => rows} = data, _) do
        rows_html =
          Enum.map_join(rows, "\n", fn row ->
            class = (row["class"] && ~s( class="#{row["class"]}")) || ""
            value = row["value"]

            """
            <li#{class}>
              #{value}
            </li>
            """
          end)

        ul_id = (data["id"] && ~s( id="#{data["id"]}")) || ""
        ul_class = (data["class"] && ~s( class="#{data["class"]}")) || ""

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
      def datatable(%{"rows" => rows}, _) do
        rows_html =
          Enum.map_join(rows, "\n", fn row ->
            """
            <tr>
              <td class="key">
                #{row["key"]}
              </td>
              <td class="value">
                #{row["value"]}
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
                #{row["key"]}
              </td>
              <td class="value">
                #{row["value"]}
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
      def blockquote(%{"text" => text, "cite" => cite}, _)
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

      def blockquote(%{"text" => text}, _) do
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
      def columns(cols, _) do
        col_html =
          for col <- cols do
            c =
              Enum.reduce(col["data"], [], fn d, acc ->
                [apply(__MODULE__, String.to_atom(d["type"]), [d["data"], []]) | acc]
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

      defoverridable columns: 2

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
                      #{Map.get(item, "caption")}
                    </div>
                  </div>
                  <div class="villain-timeline-item-content">
                    <div class="villain-timeline-item-content-inner">
                      #{Map.get(item, "text")}
                    </div>
                  </div>
                </li>
                )
          end

        ~s(<ul class="villain-timeline">#{timeline_html}</ul>)
      end

      defoverridable timeline: 2

      # ...

      defp process_vars(vars), do: Enum.map(vars, &process_var(&1)) |> Enum.into(%{})

      defp process_var({name, %{"label" => label, "type" => type, "value" => value}}) do
        {name, %Villain.Var{label: label, type: type, value: value}}
      end

      defp get_base_context() do
        identity = Cache.Identity.get()

        %{}
        |> Lexer.Context.new()
        |> Lexer.Context.assign("identity", identity)
        |> Lexer.Context.assign("configs", identity.configs)
        |> Lexer.Context.assign("links", identity.links)
      end

      defp render_datasource_entries(template, entries) do
        base_context = get_base_context()

        content =
          entries
          |> Enum.map(
            &Lexer.parse_and_render(
              template.code,
              Lexer.Context.assign(base_context, "entry", &1)
            )
          )
          |> Enum.join("\n")

        context =
          base_context
          |> Lexer.Context.assign("entries", entries)
          |> Lexer.Context.assign("content", content)

        Lexer.parse_and_render(template.wrapper, context)
      end

      defp render_refs(template_code, refs, id) do
        Regex.replace(~r/%{(\w+)}/, template_code, fn _, match ->
          ref = Enum.find(refs, &(&1["name"] == match))
          render_ref(ref, id, match)
        end)
      end

      defp render_ref(nil, id, match), do: "<!-- REF #{match} missing // template: #{id}. -->"
      defp render_ref(%{"deleted" => true}, _id, _match), do: "<!-- d -->"

      defp render_ref(ref, _id, _match) do
        block = Map.get(ref, "data")
        apply(__MODULE__, String.to_atom(block["type"]), [block["data"], []])
      end
    end
  end
end
