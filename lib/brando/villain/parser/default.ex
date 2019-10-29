defmodule Brando.Villain.Parser.Default do
  @moduledoc """
  Default parser for Villain.
  """

  @behaviour Brando.Villain.Parser

  import Brando.Utils, only: [img_url: 3, media_url: 0]
  import Ecto.Query

  @doc """
  Convert header to HTML
  """
  def header(%{"text" => text, "level" => level, "anchor" => anchor}) do
    h = header(%{"text" => text, "level" => level})
    ~s(<a name="#{anchor}"></a>#{h})
  end

  def header(%{"text" => header_text, "level" => level}) do
    header_size = "h#{level}"
    "<#{header_size}>" <> header_text <> "</#{header_size}>"
  end

  def header(%{"text" => header_text}) do
    "<h1>" <> header_text <> "</h1>"
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

  @doc """
  Convert text to HTML through Markdown
  """
  def text(%{"text" => markdown_data, "type" => type}) do
    markdown_data =
      if type == "lead" and byte_size(markdown_data) > 0 do
        markdown_data <> "\n{: .lead}"
      else
        markdown_data
      end

    Earmark.as_html!(markdown_data, %Earmark.Options{breaks: true})
  end

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

  @doc """
  Convert YouTube and Vimeo videos to iframe html
  """
  def video(%{"remote_id" => remote_id, "source" => "youtube"}) do
    """
    <div class="video-wrapper">
      <iframe width="420"
              height="315"
              src="//www.youtube.com/embed/#{remote_id}?autoplay=1&controls=0&showinfo=0&rel=0"
              frameborder="0"
              allowfullscreen>
      </iframe>
    </div>
    """
  end

  def video(%{"remote_id" => remote_id, "source" => "vimeo"}) do
    """
    <div class="video-wrapper">
      <iframe src="//player.vimeo.com/video/#{remote_id}"
              width="500"
              height="281"
              frameborder="0"
              webkitallowfullscreen
              mozallowfullscreen
              allowfullscreen>
      </iframe>
    </div>
    """
  end

  @doc """
  Convert image to html, with caption and credits and optional link
  """
  def image(%{"url" => url, "title" => title, "credits" => credits} = data) do
    {link_open, link_close} =
      if Map.get(data, "link", "") != "" do
        {~s(<a href="#{data["link"]}" title="#{title}">), ~s(</a>)}
      else
        {"", ""}
      end

    """
    <div class="img-wrapper">
      #{link_open}<img src="#{url}" alt="#{title}/#{credits}" class="img-fluid" />#{link_close}
      <div class="image-info-wrapper">
        <div class="image-title">
          #{title}
        </div>
        <div class="image-credits">
          #{credits}
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Slideshow
  """
  def slideshow(%{"imageseries" => series_slug, "size" => size}) do
    series =
      Brando.repo().all(
        from is in Brando.ImageSeries,
          join: c in assoc(is, :image_category),
          join: i in assoc(is, :images),
          where: c.slug == "slideshows" and is.slug == ^series_slug,
          order_by: i.sequence,
          preload: [image_category: c, images: i]
      )
      |> List.first()

    images =
      Enum.map_join(series.images, "\n", fn img ->
        src = img_url(img.image, String.to_atom(size), prefix: media_url())
        ~s(<li><img src="#{src}" /></li>)
      end)

    """
    <div class="flexslider flex-viewport">
      <ul class="slides">
        #{images}
      </ul>
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
  def list(%{"text" => markdown_data}) do
    Earmark.as_html!(markdown_data)
  end

  @doc """
  Html -> html. Easy as pie.
  """
  def html(%{"text" => html_data}) do
    html_data
  end

  @doc """
  Strip out comments
  """
  def comment(_), do: ""

  @doc """
  Markdown -> html
  """
  def markdown(%{"text" => markdown_data}) do
    Earmark.as_html!(markdown_data, %Earmark.Options{breaks: true})
  end

  @doc """
  Converts quote to html.
  """
  def blockquote(%{"text" => bq, "cite" => cite}) when byte_size(cite) > 0 do
    html = "#{bq}\n>\n> -- <cite>#{cite}</cite>"
    Earmark.as_html!(html)
  end

  def blockquote(%{"text" => bq}) do
    Earmark.as_html!(bq)
  end

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
            class -> class
          end

        ~s(<div class="#{class}">#{Enum.reverse(c)}</div>)
      end

    ~s(<div class="row">#{col_html}</div>)
  end
end
