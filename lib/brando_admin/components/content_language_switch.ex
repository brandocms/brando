defmodule BrandoAdmin.Components.ContentLanguageSwitch do
  use Surface.LiveComponent
  alias BrandoAdmin.Components.Modal

  data language_short, :string
  data language_long, :string

  data languages, :list
  data show_language_picker, :boolean

  def mount(socket) do
    {:ok, assign(socket, :show_language_picker, false)}
  end

  def update(%{current_user: %{config: %{content_language: content_language}}} = assigns, socket) do
    language_short = content_language

    language_long =
      case Enum.find(Brando.config(:languages), &(&1[:value] == language_short)) do
        nil -> "Error"
        lang -> lang[:text]
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:content_language, content_language)
     |> assign(:language_short, language_short)
     |> assign(:language_long, language_long)
     |> assign(:languages, Brando.config(:languages))}
  end

  def render(assigns) do
    ~F"""
    <div class="content-language-selector" :on-click="show_language_picker">
      <div class="inner">
        <h2>Current content language</h2>
        <div class="selected-language">
          <div class="circle">
            {@language_short}
          </div>
          <span>{@language_long}</span>
        </div>

        {#if @show_language_picker}
          <div class="instructions">
            Choose the content language you wish to edit entries in
          </div>
          <div class="languages">
            {#for language <- @languages}
              <button
                type="button"
                :on-click="select_language"
                phx-value-id={language[:value]}
                phx-page-loading>
                {language[:text]}
              </button>
            {/for}
          </div>
        {/if}
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

  def handle_event("show_modal", _, socket) do
    Modal.show("content-language-selector-modal")
    {:noreply, socket}
  end
end
