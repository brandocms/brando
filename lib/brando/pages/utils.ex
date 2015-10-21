defmodule Brando.Pages.Utils do

  import Ecto.Query
  alias Brando.PageFragment

  def render_fragment(key) do
    language = Gettext.locale()
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