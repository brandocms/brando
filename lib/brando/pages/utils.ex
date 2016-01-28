defmodule Brando.Pages.Utils do
  @moduledoc """
  Brando page utilities.
  """
  import Ecto.Query
  alias Brando.PageFragment

  @doc """
  Renders a page fragment by `key`.

  ## Example:

      render_fragment("my/fragment", Gettext.get_locale(MyApp.Gettext)
      render_fragment("my/fragment", "en")

  If no language is passed, default language set in `brando.exs` will be used.
  If the fragment isn't found, it will render an error box.
  """
  def render_fragment(key, language \\ nil) do
    language = language && language || Brando.config(:default_language)
    fragment = Brando.repo.one(
      from p in PageFragment,
        where: p.key == ^key and
               p.language == ^language
    )
    case fragment do
      nil -> ~s(<div class="page-fragment-missing">
                  <strong>Missing page fragment</strong> <br />
                  key..: #{key}<br />
                  lang.: #{language}
                </div>) |> Phoenix.HTML.raw
      fragment -> Phoenix.HTML.raw(fragment.html)
    end
  end
end