defmodule Brando.Villain.Tags.HeadlessRef do
  @moduledoc """
  Headless refs are useful if you want to tackle the ref directly, without
  going through the parser.

  For example a table:

      <div class="table">
        {% headless_ref refs.table %}
        {% hide %}
          {% assign rows = refs.table | rows %}
          {% for row in rows %}
            {% for col in row.cols %}
              {{ col.value }}
            {% endfor %}
          {% endfor %}
        {% endhide %}
      </div>

  """
  @behaviour Liquex.Tag

  import NimbleParsec
  alias Liquex.Parser.Argument
  alias Liquex.Parser.Literal
  alias Liquex.Parser.Tag

  @impl true
  def parse() do
    ignore(Tag.open_tag())
    |> ignore(string("headless_ref"))
    |> ignore(Literal.whitespace())
    |> unwrap_and_tag(Argument.argument(), :ref)
    |> ignore(Tag.close_tag())
  end

  @impl true
  def render(_, context) do
    {"", context}
  end
end
