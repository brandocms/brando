defmodule E2eProjectWeb.LivePreview do
  use Brando.LivePreview
  alias Brando.Pages

  preview_target Pages.Page do
    layout {E2eProjectWeb.Layouts, "app"}
    template fn e -> {E2eProjectWeb.PageHTML, e.template} end
    template_section fn entry -> entry.uri end
    template_prop :page
  end
end
