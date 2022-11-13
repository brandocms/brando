defmodule <%= application_module %>Web.LivePreview do
  use Brando.LivePreview
  alias Brando.Pages

  preview_target Pages.Page do
    layout {<%= application_module %>Web.Layouts, "app"}
    template fn e -> {<%= application_module %>Web.PageHTML, e.template} end
    template_section fn entry -> entry.uri end
    template_prop :page
  end
end
