defmodule Brando.Villain.Parser do
  @moduledoc """
  Defines callbacks for the Villain.Parser behaviour.
  """

  @doc "Parses a comment"
  @callback comment(%{String.t() => any}) :: String.t()

  @doc "Parses a header"
  @callback header(%{String.t() => any}) :: String.t()

  @doc "Parses text/paragraphs"
  @callback text(%{String.t() => any}) :: String.t()

  @doc "Parses video"
  @callback video(%{String.t() => any}) :: String.t()

  @doc "Parses map"
  @callback map(%{String.t() => any}) :: String.t()

  @doc "Parses image"
  @callback image(%{String.t() => any}) :: String.t()

  @doc "Parses slideshow"
  @callback slideshow(%{String.t() => any}) :: String.t()

  @doc "Parses divider"
  @callback divider(%{String.t() => any}) :: String.t()

  @doc "Parses list"
  @callback list(%{String.t() => any}) :: String.t()

  @doc "Parses blockquote"
  @callback blockquote(%{String.t() => any}) :: String.t()

  @doc "Parses columns"
  @callback columns(%{String.t() => any}) :: String.t()

  @doc "Parses datatables"
  @callback datatable(%{String.t() => any}) :: String.t()

  @doc "Parses markdown"
  @callback markdown(%{String.t() => any}) :: String.t()

  @doc "Parses html"
  @callback html(%{String.t() => any}) :: String.t()

  @doc "Parses template"
  @callback template(%{String.t() => any}) :: String.t()

  @doc "Parses datasource"
  @callback datasource(%{String.t() => any}) :: String.t()

  defmacro __using__(_) do
    quote do
      @behaviour Brando.Villain.Parser
      import Brando.HTML
      import Phoenix.HTML

      @doc """
      Convert header to HTML
      """
      def header(%{"text" => text, "level" => level, "anchor" => anchor}) do
        h = header(%{"text" => text, "level" => level})
        ~s(<a name="#{anchor}"></a>#{h})
      end

      def header(%{"text" => text, "level" => level} = data) do
        classes =
          if Map.get(data, "class", nil) do
            ~s( class="#{Map.get(data, "class")}")
          else
            ""
          end

        header_size = "h#{level}"
        "<#{header_size}#{classes}>" <> nl2br(text) <> "</#{header_size}>"
      end

      def header(%{"text" => text}) do
        "<h1>" <> nl2br(text) <> "</h1>"
      end
      defoverridable header: 1

      defp try(map, keys) do
        Enum.reduce(keys, map, fn key, acc ->
          if acc, do: Map.get(acc, key)
        end)
      end

      def datasource(%{
            "module" => module,
            "type" => "many",
            "query" => query,
            "template" => template_id,
            "wrapper" => wrapper
          }) do
        {:ok, entries} = Brando.Datasource.get_many(module, query)
        {:ok, template} = Brando.Villain.get_template(template_id)

        content =
          for entry <- entries do
            Regex.replace(~r/\${entry\:(\w+)\|?(\w+)?}/, template.code, fn _, key, param ->
              var_path =
                key
                |> String.split(".")
                |> Enum.map(&String.to_existing_atom/1)

              case try(entry, var_path) do
                nil ->
                  "${entry:#{key}}"

                %Brando.Type.Image{} = img ->
                  key = param != "" && String.to_existing_atom(param) || :xlarge
                  mod = Module.concat([module])

                  picture_tag(img,
                    key: key,
                    picture_class: "picture-img",
                    width: true,
                    height: true,
                    placeholder: :svg,
                    lazyload: true,
                    prefix: Brando.Utils.media_url(),
                    srcset: {mod, List.last(var_path)},
                    cache: entry.updated_at
                  ) |> safe_to_string

                var when is_integer(var) ->
                  Integer.to_string(var)

                var ->
                  case param do
                    "" -> var




                  end
              end
            end)
          end
          |> Enum.join("\n")

        String.replace(wrapper, "${CONTENT}", content)
      end
      defoverridable datasource: 1

      @doc """
      Convert text to HTML through Markdown
      """
      def text(%{"text" => text} = params) do
        text =
          case Map.get(params, "type") do
            nil -> text
            "paragraph" -> text
            type -> "<div class=\"#{type}\">#{text}</div>"
          end

        Earmark.as_html!(text, %Earmark.Options{breaks: true})
      end
      defoverridable text: 1

      @doc """
      Html -> html. Easy as pie.
      """
      def html(%{"text" => html}), do: html
      defoverridable html: 1

      @doc """
      Markdown -> html
      """
      def markdown(%{"text" => markdown}) do
        Earmark.as_html!(markdown, %Earmark.Options{breaks: false})
      end
      defoverridable markdown: 1

      @doc """
      Convert GMaps url to iframe html
      """
      def map(%{"embed_url" => embed_url, "source" => "gmaps"}) do
        ~s(<div class="map-wrapper">
             <iframe width="420"
                     height="315"
                     src="#{embed_url}"
                     frameborder="0"
                     allowfullscreen>
             </iframe>
           </div>)
      end
      defoverridable map: 1

      @doc """
      Convert YouTube video to iframe html
      """
      def video(%{"remote_id" => remote_id, "source" => "youtube"}) do
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

      def video(%{"remote_id" => remote_id, "source" => "vimeo"}) do
        ~s(<div class="video-wrapper">
             <iframe src="//player.vimeo.com/video/#{remote_id}"
                     width="500"
                     height="281"
                     frameborder="0"
                     webkitallowfullscreen
                     mozallowfullscreen
                     allowfullscreen>
             </iframe>
           </div>)
      end

      @doc """
      Convert file video to html
      """
      def video(%{"remote_id" => src, "source" => "file"} = data) do
        video_tag(src, %{width: data["width"], height: data["height"], preload: true, opacity: 0.1})
      end
      defoverridable video: 1

      @doc """
      Convert image to html, with caption and credits and optional link
      """
      def picture(data) do
        title = Map.get(data, "title", "")
        credits = Map.get(data, "credits", "")
        alt = Map.get(data, "alt", nil)

        link = Map.get(data, "link", "")
        img_class = Map.get(data, "img_class", "")
        picture_class = Map.get(data, "picture_class", "")
        srcset = Map.get(data, "srcset", "")
        media_queries = Map.get(data, "media_queries", "")

        {link_open, link_close} =
          if link != "" do
            {~s(<a href="#{data["link"]}" title="#{title}">), ~s(</a>)}
          else
            {"", ""}
          end

        title = if title == "", do: nil, else: title
        credits = if credits == "", do: nil, else: credits

        caption = ""

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
            picture_class: "picture-img",
            img_class: img_class,
            picture_class: picture_class,
            media_queries: media_queries,
            alt: alt,
            width: true,
            height: true,
            placeholder: :svg,
            lazyload: true,
            srcset: srcset
            # cache: img.updated_at,
          )
          |> safe_to_string

        """
        <div class="picture-wrapper">
          #{link_open}
          #{ptag}
          #{link_close}
          #{caption}
        </div>
        """
      end
      defoverridable picture: 1

      @doc """
      Convert image to html, with caption and credits and optional link
      """
      def image(data) do
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
      defoverridable image: 1

      @doc """
      Slideshow
      """
      def slideshow(%{"images" => images}) do
        images_html =
          Enum.map_join(images, "\n", fn img ->
            src = img["sizes"]["xlarge"]

            """
            <div class="glide-slide">
              <img class="img-fluid" src="#{src}" />
              <div class="overlay-zoom">
                <a href="#{src}" class="zoom plain" data-lightbox="#{src}">
                  +
                </a>
              </div>
            </div>
            """
          end)

        """
        <div class="glide-wrapper">
          <div class="glide">
            #{images_html}
          </div>
        </div>
        """
      end
      defoverridable slideshow: 1

      @doc """
      Datatable
      """
      def datatable(rows) do
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
      defoverridable datatable: 1

      @doc """
      Convert divider/hr to html
      """
      def divider(_), do: ~s(<hr>)
      defoverridable divider: 1

      @doc """
      Convert list to html through Markdown
      """
      def list(%{"text" => list}), do: Earmark.as_html!(list)
      defoverridable list: 1

      @doc """
      Converts quote to html.
      """
      def blockquote(%{"text" => blockquote, "cite" => cite})
          when byte_size(cite) > 0 do
        html = blockquote <> "\n>\n> -- <cite>#{cite}</cite>"
        Earmark.as_html!(html)
      end

      def blockquote(%{"text" => blockquote}) do
        Earmark.as_html!(blockquote)
      end
      defoverridable blockquote: 1

      @doc """
      Strip comments
      """
      def comment(_), do: ""
      defoverridable comment: 1

      @doc """
      Convert columns to html. Recursive parsing.
      """
      def columns(cols) do
        col_html =
          for col <- cols do
            c =
              Enum.reduce(col["data"], [], fn d, acc ->
                [apply(__MODULE__, String.to_atom(d["type"]), [d["data"]]) | acc]
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
      defoverridable columns: 1

      @doc """
      Convert template to html.
      """
      def template(%{"code" => code, "refs" => refs}) do
        Regex.replace(~r/%{(\w+)}/, code, fn _, match ->
          ref = Enum.find(refs, &(&1["name"] == match))
          block = Map.get(ref, "data")
          apply(__MODULE__, String.to_atom(block["type"]), [block["data"]])
        end)
      end

      @doc """
      Convert template to html.
      """
      def template(%{"id" => id, "refs" => refs}) do
        {:ok, template} = Brando.Villain.get_template(id)

        Regex.replace(~r/%{(\w+)}/, template.code, fn _, match ->
          ref = Enum.find(refs, &(&1["name"] == match))

          if ref do
            block = Map.get(ref, "data")
            apply(__MODULE__, String.to_atom(block["type"]), [block["data"]])
          else
            "<!-- REF #{match} missing // template: #{id}. -->"
          end
        end)
      end
      defoverridable template: 1

      @doc """
      Timeline
      """
      def timeline(items) do
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
      defoverridable timeline: 1
      # ...
    end
  end
end
