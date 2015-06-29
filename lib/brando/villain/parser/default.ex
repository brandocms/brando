defmodule Brando.Villain.Parser.Default do
  @moduledoc """
  Default parser for Villain.
  """
  @behaviour Brando.Villain.Parser

  @doc """
  Convert header to HTML
  """
  def header(%{text: text, level: level}) do
    header_size = "h#{level}"
    "<#{header_size}>" <> text <> "</#{header_size}>"
  end

  def header(%{text: text}) do
    "<h1>" <> text <> "</h1>"
  end

  @doc """
  Convert text to HTML through Markdown
  """
  def text(%{text: text}) do
    Earmark.to_html(text)
  end

  @doc """
  Convert YouTube video to iframe html
  """
  def video(%{remote_id: remote_id, source: "youtube"}) do
    ~s(<iframe width="420" height="315" src="//www.youtube.com/embed/#{remote_id}" frameborder="0" allowfullscreen></iframe>)
  end

  @doc """
  Convert Vimeo video to iframe html
  """
  def video(%{remote_id: remote_id, source: "vimeo"}) do
    ~s(<iframe src="//player.vimeo.com/video/#{remote_id}" width="500" height="281" frameborder="0" webkitallowfullscreen mozallowfullscreen allowfullscreen></iframe>)
  end

  @doc """
  Convert image to html, with caption and credits
  """
  def image(%{url: url, caption: caption, credits: credits}) do
    ~s(<img src="#{url}" alt="#{caption} / #{credits}" class="img-responsive" />)
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
  def list(%{text: list}) do
    Earmark.to_html(list)
  end

  @doc """
  Convert columns to html. Recursive parsing.
  """
  def columns(cols) do
    for col <- cols do
      c = Enum.reduce(col[:data], [], fn(d, acc) ->
        [apply(__MODULE__, String.to_atom(d[:type]), [d[:data]])|acc]
      end)
      ~s(<div class="#{col[:class]}">#{Enum.reverse(c)}</div>)
    end
  end
end