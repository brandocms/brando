defmodule <%= application_module %>Web.LivePreview do
  use Brando.LivePreview
  alias Brando.Pages

  preview_target Pages.Page do
    layout_module <%= application_module %>Web.LayoutView
    view_module <%= application_module %>Web.PageView
    view_template fn entry -> entry.template end
    template_section fn entry -> entry.uri end
    template_prop :page

    assign :navigation, fn _ ->
      Brando.Navigation.get_menu("main", Brando.config(:default_language)) |> elem(1)
    end

    assign :language, fn _ ->
      Brando.config(:default_language)
    end

    assign :partials, fn _ ->
      fragment_opts = %{
        filter: %{parent_key: "partials"},
        cache: {:ttl, :infinite}
      }

      Pages.get_fragments(fragment_opts) |> elem(1)
    end
  end
end
