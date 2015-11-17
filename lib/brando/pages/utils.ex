defmodule Brando.Pages.Utils do

  import Ecto.Query
  alias Brando.PageFragment

  @doc """
  Renders a page fragment by `key`.

  ## Example:

      render_fragment("my/fragment", Gettext.get_locale(MyApp.Gettext)
      render_fragment("my/fragment", "en")

  If no language is passed, "en" will be used as default.
  If the fragment isn't found, it will render an error box.
  """
  def render_fragment(key, language \\ "en") do
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