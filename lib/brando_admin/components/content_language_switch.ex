defmodule BrandoAdmin.Components.ContentLanguageSwitch do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias Brando.Translations
  alias BrandoAdmin.Components.Form.Translation
  alias Phoenix.HTML

  @doc "Whether the switch is offered: the site has more than one language (`Brando.Languages`)."
  def show?, do: length(Brando.Languages.languages()) > 1

  def mount(socket) do
    {:ok, socket |> assign(:show_language_picker, false) |> assign(:options, %{})}
  end

  def update(%{current_user: %{config: %{content_language: content_language}}} = assigns, socket) do
    # The site's languages (`Brando.Languages`)
    languages = Brando.Languages.languages()

    language_long =
      case Enum.find(languages, &(to_string(&1[:value]) == to_string(content_language))) do
        nil ->
          # Not one of the site's languages: the site's default
          default = to_string(Brando.Languages.default_language())
          send(self(), {:set_content_language, default})
          Enum.find_value(languages, default, &(to_string(&1[:value]) == default && &1[:text]))

        lang ->
          lang[:text]
      end

    socket =
      socket
      |> assign(assigns)
      |> assign_new(:entry, fn -> nil end)
      |> assign(:content_language, content_language)
      |> assign(:languages, languages)

    # In an entry's form, the switch is on the entry's language
    # (`content_language_entry` in `BrandoAdmin.LiveView.Form.Hooks`)
    socket =
      case socket.assigns.entry do
        %{language: language} ->
          socket
          |> assign(:current, language)
          |> assign(
            :language_long,
            Enum.find_value(languages, language, &(to_string(&1[:value]) == language && &1[:text]))
          )

        nil ->
          socket
          |> assign(:current, to_string(content_language))
          |> assign(:language_long, language_long)
      end

    {:ok, if(socket.assigns.show_language_picker, do: assign_options(socket), else: socket)}
  end

  # What each language does in an entry's form: `:open` its version (with
  # its URL), `:create` a translation, or nothing, saying why (`:trashed`,
  # `:none`, `:unavailable` for a version the editor may not read). Read
  # when the list opens, and again for a choice: the versions the editor may
  # read (`Translations.versions_by_language/3`), and on a synchronized type
  # the languages without one (`Translations.missing_languages/2`), as the
  # form's translation panel and the language versions drawer have them.
  defp assign_options(%{assigns: %{entry: %{schema: schema, id: id}, current_user: user}} = socket) do
    entry = Brando.Repo.get(schema, id)
    assign(socket, :options, if(entry, do: options(schema, entry, user), else: %{}))
  end

  defp assign_options(socket), do: assign(socket, :options, %{})

  defp options(schema, entry, user) do
    versions = Translations.versions_by_language(schema, entry, user)
    missing = Translations.missing_languages(schema, entry)
    create? = Translations.synchronized?(schema) and Translation.can_create?(schema, user)

    for code <- Brando.Languages.codes(), code != to_string(entry.language), into: %{} do
      option =
        case versions do
          %{^code => %{deleted_at: %DateTime{}}} -> :trashed
          %{^code => version} -> url(schema, version)
          _ -> without_version(code, missing, create?)
        end

      {code, option}
    end
  end

  # A language with no version the editor may read: one with no version at
  # all, or one with a version they may not read (not in `missing`)
  defp without_version(code, missing, create?) do
    cond do
      code not in missing -> :unavailable
      create? -> :create
      true -> :none
    end
  end

  defp url(schema, version) do
    case schema.__admin_route__(:update, [version.id]) do
      url when is_binary(url) -> {:open, url}
      _ -> :unavailable
    end
  rescue
    _ -> :unavailable
  end

  def render(assigns) do
    ~H"""
    <div
      class={["content-language-selector", @show_language_picker && "open"]}
      phx-click-away={@show_language_picker && JS.push("hide_language_picker", target: @myself)}
    >
      <%!-- Keep the trigger after a stable slot: pending phx-remove nodes are
           otherwise moved after it while their exit is still running. --%>
      <div id="content-language-panel">
        <div
          :if={@show_language_picker}
          id="content-language-options"
          class="languages"
          role="listbox"
          aria-label={gettext("Content language")}
          phx-mounted={JS.dispatch("b:ui-reveal")}
          phx-remove={JS.dispatch("b:ui-reveal", detail: %{remove: true}, blocking: true)}
        >
          <.option
            :for={language <- @languages}
            code={to_string(language[:value])}
            text={language[:text]}
            current={@current}
            option={@options[to_string(language[:value])]}
            entry={@entry}
            myself={@myself}
          />
        </div>
      </div>
      <button
        id="content-language-trigger"
        type="button"
        class="current-language"
        aria-haspopup="listbox"
        aria-controls="content-language-options"
        aria-expanded={to_string(@show_language_picker)}
        title={gettext("Choose the content language you wish to edit entries in")}
        phx-click={JS.push("show_language_picker", target: @myself)}
      >
        <.icon name="globe" />
        <span class="label">{content_in(@language_long)}</span>
        <.icon name="chevrons-up-down" class="toggle" />
      </button>
    </div>
    """
  end

  attr :code, :string, required: true
  attr :text, :string, required: true
  attr :current, :string, required: true
  attr :option, :any, required: true
  attr :entry, :map, required: true
  attr :myself, :any, required: true

  # The entry's form, a version to open or a translation to create: the
  # form asks about unsaved changes first (`data-leaves-form`, `draftRecovery.js`)
  defp option(%{code: code, current: code} = assigns) do
    ~H"""
    <button type="button" role="option" aria-selected="true" class="current" phx-click={pick(@myself)} phx-value-id={@code}>
      {@text}
      <.icon name="check" />
    </button>
    """
  end

  defp option(%{entry: nil} = assigns) do
    ~H"""
    <button type="button" role="option" aria-selected="false" phx-click={pick(@myself)} phx-value-id={@code}>
      {@text}
    </button>
    """
  end

  defp option(%{option: {:open, _url}} = assigns) do
    ~H"""
    <button
      type="button"
      role="option"
      aria-selected="false"
      data-leaves-form
      phx-click={pick(@myself)}
      phx-value-id={@code}
    >
      {@text}
    </button>
    """
  end

  defp option(%{option: :create} = assigns) do
    ~H"""
    <button
      type="button"
      role="option"
      aria-selected="false"
      data-leaves-form
      phx-click={JS.push("create_translation", value: %{language: @code}, target: "[data-entry-form='#{@entry.id}']")}
      phx-value-id={@code}
    >
      {@text}
      <span class="hint">{gettext("Create translation")}</span>
    </button>
    """
  end

  defp option(assigns) do
    ~H"""
    <button type="button" role="option" aria-selected="false" aria-disabled="true" disabled phx-value-id={@code}>
      {@text}
      <span class="hint">{unavailable(@option)}</span>
    </button>
    """
  end

  defp pick(myself), do: JS.push("select_language", target: myself)

  defp unavailable(:trashed), do: gettext("In the trash")
  defp unavailable(:unavailable), do: gettext("No access")
  defp unavailable(_none), do: gettext("No version")

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

  # In an entry's form, a language opens the entry's version in it, when the
  # editor may read one, and sets the preference too; any other choice is
  # refused, and the form stays. Elsewhere it sets the preference.
  def handle_event("select_language", %{"id" => id}, %{assigns: %{current: id}} = socket),
    do: {:noreply, assign(socket, :show_language_picker, false)}

  def handle_event("select_language", %{"id" => id}, %{assigns: %{entry: nil}} = socket) do
    send(self(), {:set_content_language, id})
    {:noreply, assign(socket, :show_language_picker, false)}
  end

  def handle_event("select_language", %{"id" => id}, socket) do
    socket = assign_options(socket)

    case socket.assigns.options do
      %{^id => {:open, url}} ->
        # Here, not through `{:set_content_language, _}`: the form is left at once
        {:ok, _user} =
          Brando.Users.update_user(socket.assigns.current_user, %{config: %{content_language: id}}, :system,
            show_notification: false
          )

        {:noreply, socket |> assign(:show_language_picker, false) |> push_navigate(to: url)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("hide_language_picker", _, socket) do
    {:noreply, assign(socket, :show_language_picker, false)}
  end

  def handle_event("show_language_picker", _, socket) do
    if socket.assigns.show_language_picker,
      do: {:noreply, assign(socket, :show_language_picker, false)},
      else: {:noreply, socket |> assign(:show_language_picker, true) |> assign_options()}
  end
end
