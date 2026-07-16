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

  Or a gallery:

      <div class="gallery">
        {% headless_ref refs.gallery %}
        {% hide %}
          {% assign images = refs.gallery.data.data.images %}
          {% for image in images %}
            {% picture image {
              sizes: 'auto',
              lazyload: true,
              placeholder: 'dominant_color_faded',
              srcset: 'default',
              prefix: '/media'
            } %}
          {% endfor %}
        {% endhide %}
      </div>
  """
  @behaviour Liquex.Tag

  alias Brando.Villain.LiquexParser.TagGrammar

  @impl true
  def parse, do: TagGrammar.parse(:headless_ref)

  @impl true
  def render(_, context) do
    {"", context}
  end
end
