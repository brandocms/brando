defmodule <%= module %>View do
  use <%= web_module %>, :view
  # import <%= web_module %>.Gettext
  use Phoenix.Component

  def list_<%= plural %>(assigns) do
    ~H"""
    <div class="<%= plural %>">
      <div class="inner">
        <%%= for <%= singular %> <- @<%= plural %> do %>
        <a href={absolute_url(<%= singular %>)} class="<%= singular %>">
          <%= if img_fields do %><.picture src={<%= singular %>.cover} opts={[
            prefix: media_url(),
            lazyload: true,
            srcset: {<%= inspect schema_module %>, :cover},
            placeholder: :dominant_color,
            moonwalk: true
          ]} /><% end %>
          <div class="info">
            <section class="meta">
              <div class="time">
                <%%= @entry.updated_at %>
              </div>
            </section>
            <h2>
              <%%= @entry.title %>
            </h2>
            <section class="more">
              <p>Read more &rarr;</p>
            </section>
          </div>
        </a>
        <%% end %>
      </div>
    </div>
    """
  end
end
