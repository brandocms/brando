<%
  index_path = if language, do: "\#{@base_path}", else: public_route
  # A controller from an older template assigns no base_path.
  base_path = if language, do: "    assigns = Map.put_new(assigns, :base_path, #{inspect(public_route)})\n\n", else: ""
%>defmodule <%= inspect html_module %> do
<%= if site_layouts do %>  use BrandoWeb, :html

  def index(assigns) do
<%= base_path %>    ~H"""
    <main id="content">
      <h1><%= Phoenix.Naming.humanize(plural) %></h1>
      <ul>
        <li :for={entry <- @entries}>
          <.link href={"<%= index_path %>/#{entry.<%= param %>}"}>{entry.<%= main_field %>}</.link>
        </li>
      </ul>
    </main>
    """
  end

  def show(assigns) do
<%= base_path %>    ~H"""
    <main id="content">
      <article>
        <h1>{@entry.<%= main_field %>}</h1><%= for field <- blocks do %>
        <Brando.HTML.render_blocks entry={@entry}<%= if field != :blocks, do: " field={:#{field}}" %> /><% end %>
      </article>
      <.link href=<%= if language, do: "{@base_path}", else: inspect(public_route) %>>Back to <%= String.replace(plural, "_", " ") %></.link>
    </main>
    """
  end
<% else %>  use <%= web_module %>, :html

  def index(assigns) do
<%= base_path %>    ~H"""
    <h1><%= Phoenix.Naming.humanize(plural) %></h1>
    <ul>
      <li :for={entry <- @entries}>
        <.link href={"<%= index_path %>/#{entry.<%= param %>}"}>{entry.<%= main_field %>}</.link>
      </li>
    </ul>
    """
  end

  def show(assigns) do
<%= base_path %>    ~H"""
    <h1>{@entry.<%= main_field %>}</h1><%= for field <- blocks do %>
    <Brando.HTML.render_blocks entry={@entry}<%= if field != :blocks, do: " field={:#{field}}" %> /><% end %>
    <.link href=<%= if language, do: "{@base_path}", else: inspect(public_route) %>>Back to <%= String.replace(plural, "_", " ") %></.link>
    """
  end
<% end %>end
