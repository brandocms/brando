defmodule <%= inspect html_module %> do
  use <%= web_module %>, :html

  def index(assigns) do
    ~H"""
    <h1><%= Phoenix.Naming.humanize(plural) %></h1>
    <ul>
      <li :for={entry <- @entries}>
        <.link href={"<%= public_route %>/#{entry.id}"}>{entry.<%= main_field %>}</.link>
      </li>
    </ul>
    """
  end

  def show(assigns) do
    ~H"""
    <h1>{@entry.<%= main_field %>}</h1>
    <.link href="<%= public_route %>">Back to <%= String.replace(plural, "_", " ") %></.link>
    """
  end
end
