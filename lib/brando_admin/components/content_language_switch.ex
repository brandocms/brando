defmodule BrandoAdmin.Components.ContentLanguageSwitch do
  use BrandoAdmin, :live_component
  import Brando.Gettext

  def mount(socket) do
    {:ok, assign(socket, :show_language_picker, false)}
  end

  def update(%{current_user: %{config: %{content_language: content_language}}} = assigns, socket) do
    language_long =
      case Enum.find(Brando.config(:languages), &(&1[:value] == content_language)) do
        nil ->
          # The language isn't one of the configured languages. Set to first
          first_lang = Brando.config(:languages) |> List.first()
          send(self(), {:set_content_language, first_lang[:value]})
          first_lang[:text]

        lang ->
          lang[:text]
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:content_language, content_language)
     |> assign(:language_long, language_long)
     |> assign(:languages, Brando.config(:languages))}
  end

  def render(assigns) do
    ~H"""
    <div class="content-language-selector" phx-click={JS.push("show_language_picker", target: @myself)}>
      <div class="inner">
        <div class="top">
          <h2><%= gettext "Current content language" %></h2>
          <div class="selected-language">
            <div class="circle">
              <%= @content_language %>
            </div>
          </div>
        </div>

        <%= if @show_language_picker do %>
          <div class="instructions">
            <%= gettext "Choose the content language you wish to edit entries in" %>
          </div>
          <div class="languages">
            <%= for language <- @languages do %>
              <button
                type="button"
                phx-click={JS.push("select_language", target: @myself)}
                phx-value-id={language[:value]}
                phx-page-loading>
                <%= language[:text] %>
              </button>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  def handle_event(
        "select_language",
        %{"id" => id},
        %{assigns: %{content_language: content_language}} = socket
      ) do
    case content_language == id do
      true ->
        {:noreply, socket |> assign(:show_language_picker, false)}

      false ->
        send(self(), {:set_content_language, id})
        {:noreply, socket |> assign(:show_language_picker, false)}
    end
  end

  def handle_event("show_language_picker", _, socket) do
    {:noreply, assign(socket, :show_language_picker, true)}
  end
end
