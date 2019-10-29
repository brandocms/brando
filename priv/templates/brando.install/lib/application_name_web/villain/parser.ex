defmodule <%= application_module %>.Villain.Parser do
  @moduledoc """
  Default parser for Villain.
  """
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
    "<#{header_size}#{classes} data-moonwalk>" <> text <> "</#{header_size}>"
  end

  def header(%{"text" => text}) do
    "<h1 data-moonwalk>" <> text <> "</h1>"
  end

  @doc """
  Convert text to HTML through Markdown
  """
  def text(%{"text" => text} = params) do
    text =
      case Map.get(params, "type") do
        nil  -> text
        "paragraph" -> text
        type -> "<div class=\"#{type}\">#{text}</div>"
      end

    Earmark.as_html!(text, %Earmark.Options{breaks: true})
  end

  @doc """
  Html -> html. Easy as pie.
  """
  def html(%{"text" => html}) do
    html
  end

  @doc """
  Markdown -> html
  """
  def markdown(%{"text" => markdown}) do
    html = Earmark.as_html!(markdown, %Earmark.Options{breaks: true})
    """
    <div data-moonwalk-children>#{html}</div>
    """
  end

  @doc """
  Convert GMaps url to iframe html
  """
  def map(%{"embed_url" => embed_url, "source" => "gmaps"}) do
    ~s(<div class="map-wrapper" data-moonwalk>
         <iframe width="420"
                 height="315"
                 src="#{embed_url}"
                 frameborder="0"
                 allowfullscreen>
         </iframe>
       </div>)
  end

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
  Convert image to html, with caption and credits and optional link
  """
  def image(data) do
    title = Map.get(data, "title", "")
    credits = Map.get(data, "credits", "")
    link = Map.get(data, "link", "")
    class = Map.get(data, "class", "")

    {link_open, link_close} = if link != "" do
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
      {"xlarge", "1900w"},
    ]

    itag =
      img_tag(data, :xlarge, [
        srcset: srcset,
        alt: "#{title}/#{credits}",
        class: class
      ]) |> safe_to_string

    """
    <div class="img-wrapper" data-moonwalk-children>
      #{link_open}
      #{itag}
      #{link_close}
      #{caption}
    </div>
    """
  end

  @doc """
  Slideshow
  """
  def slideshow(%{"images" => images}) do
    images_html = Enum.map_join images, "\n", fn(img) ->
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
    end
    """
    <div class="glide-wrapper">
      <div class="glide">
        #{images_html}
      </div>
    </div>
    """
  end

  @doc """
  Datatable
  """
  def datatable(rows) do
    rows_html =
      Enum.map_join rows, "\n", fn row ->
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
      end

    """
    <div class="data-table-wrapper">
      <table class="data-table">
        #{rows_html}
      </table>
    </div>
    """
  end

  @doc """
  Convert divider/hr to html
  """
  def divider(_) do
    ~s(<hr>)
  end

  @doc """
  Convert list to html through Markdown
  """
  def list(%{"text" => list}) do
    Earmark.as_html!(list)
  end

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

  @doc """
  Convert columns to html. Recursive parsing.
  """
  def columns(cols) do
    col_html = for col <- cols do
      c = Enum.reduce(col["data"], [], fn(d, acc) ->
        [apply(__MODULE__, String.to_atom(d["type"]), [d["data"]])|acc]
      end)
      class = case col["class"] do
        "six" -> "col-md-6"
        other -> other
      end
      ~s(<div class="#{class}">#{Enum.reverse(c)}</div>)
    end
    ~s(<div class="row">#{col_html}</div>)
  end

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

  @doc """
  Timeline
  """
  def timeline(items) do
    timeline_html = for item <- items do
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
end
