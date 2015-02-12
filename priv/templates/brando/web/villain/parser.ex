defmodule <%= application_name %>.Villain.Parser do
  @behaviour Villain.Parser

  def header(%{"text" => text}) do
    ~s(<h1>#{text}</h1>)
  end

  def text(%{"text" => text}) do
    Earmark.to_html(text)
  end

  def video(%{"remote_id" => remote_id, "source" => "youtube"}) do
    ~s(<iframe width="420" height="315" src="//www.youtube.com/embed/#{remote_id}" frameborder="0" allowfullscreen></iframe>)
  end

  def video(%{"remote_id" => remote_id, "source" => "vimeo"}) do
    ~s(<iframe src="//player.vimeo.com/video/#{remote_id}" width="500" height="281" frameborder="0" webkitallowfullscreen mozallowfullscreen allowfullscreen></iframe>)
  end

  def image(%{"url" => url} = data) do
    caption = data[:caption]
    credits = data[:credits]
    ~s(<img src="#{url}" alt="#{caption} / #{credits}" class="img-responsive" />)
  end

  def divider(_) do
    ~s(<hr>)
  end

  def list(%{"text" => list}) do
    Earmark.to_html(list)
  end

  def columns(cols) do
    for col <- cols do
      c = Enum.reduce(col["data"], [], fn(d, acc) ->
        [apply(__MODULE__, String.to_atom(d["type"]), [d["data"]])|acc]
      end)
      ~s(<div class="#{col["class"]}">#{Enum.reverse(c)}</div>)
    end
  end
end