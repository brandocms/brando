defmodule BrandoAdmin.Components.ContentLanguageSwitch do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias Phoenix.HTML

  def mount(socket) do
    {:ok, assign(socket, :show_language_picker, false)}
  end

  def update(%{current_user: %{config: %{content_language: content_language}}} = assigns, socket) do
    language_long =
      case Enum.find(Brando.config(:languages), &(&1[:value] == content_language)) do
        nil ->
          # The language isn't one of the configured languages. Set to first
          first_lang = :languages |> Brando.config() |> List.first()
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
    <div
      class={["content-language-selector", @show_language_picker && "open"]}
      phx-click-away={@show_language_picker && JS.push("hide_language_picker", target: @myself)}
    >
      <div :if={@show_language_picker} class="languages" role="listbox" aria-label={gettext("Content language")}>
        <button
          :for={language <- @languages}
          type="button"
          role="option"
          aria-selected={to_string(to_string(language[:value]) == to_string(@content_language))}
          class={[to_string(language[:value]) == to_string(@content_language) && "current"]}
          phx-click={JS.push("select_language", target: @myself)}
          phx-value-id={language[:value]}
        >
          {language[:text]}
          <.icon :if={to_string(language[:value]) == to_string(@content_language)} name="hero-check" />
        </button>
      </div>
      <button
        type="button"
        class="current-language"
        aria-haspopup="listbox"
        aria-expanded={to_string(@show_language_picker)}
        title={gettext("Choose the content language you wish to edit entries in")}
        phx-click={JS.push("show_language_picker", target: @myself)}
      >
        <.icon name="hero-globe-alt" />
        <span class="label">{content_in(@language_long)}</span>
        <.icon name="hero-chevron-up-down" class="toggle" />
      </button>
    </div>
    """
  end

  # "Content in English" / "Innhold på norsk", the language's name in bold.
  # Languages are lowercase inside a sentence in most languages, English
  # being the exception.
  defp content_in(language) do
    name = if Gettext.get_locale(Brando.Gettext) == "en", do: language, else: String.downcase(to_string(language))
    strong = "<strong>" <> (name |> HTML.html_escape() |> HTML.safe_to_string()) <> "</strong>"

    gettext("Content in %{language}", language: "\x00")
    |> HTML.html_escape()
    |> HTML.safe_to_string()
    |> String.replace("\x00", strong)
    |> HTML.raw()
  end

  def handle_event("select_language", %{"id" => id}, %{assigns: %{content_language: content_language}} = socket) do
    if content_language == id do
      {:noreply, assign(socket, :show_language_picker, false)}
    else
      send(self(), {:set_content_language, id})
      {:noreply, assign(socket, :show_language_picker, false)}
    end
  end

  def handle_event("hide_language_picker", _, socket) do
    {:noreply, assign(socket, :show_language_picker, false)}
  end

  def handle_event("show_language_picker", _, socket) do
    current_status = socket.assigns.show_language_picker
    {:noreply, assign(socket, :show_language_picker, !current_status)}
  end
end
