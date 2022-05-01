defmodule <%= application_module %>Web.LivePreview do
  use Brando.LivePreview
  alias Brando.Pages

  preview_target Pages.Page do
    layout_module <%= application_module %>Web.LayoutView
    view_module <%= application_module %>Web.PageView
    view_template fn entry -> entry.template end
    template_section fn entry -> entry.uri end
    template_prop :page
  end
end
