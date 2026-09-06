defmodule E2eProjectWeb.LivePreview do
  use Brando.LivePreview
  alias Brando.Pages

  preview_target Pages.Page do
    label "Page"
    description "Full page with its layout and content"
    layout {E2eProjectWeb.Layouts, "app"}
    template fn e -> {E2eProjectWeb.PageHTML, e.template} end
    template_section fn entry -> entry.uri end
    template_prop :page
  end

  preview_target Pages.Page do
    name :listing
    label "Page listing"
    description "Your edited page alongside published pages"
    layout {E2eProjectWeb.Layouts, "app"}
    template {E2eProjectWeb.PageHTML, "listing_preview"}
    template_prop :page
    reassign_on_change [{:pages, [:title]}, {:pages, [:uri]}]

    assign :pages, fn entry, language ->
      pages = Pages.list_pages!(%{filter: %{language: language}, status: :published, order: "asc sequence"})

      if Enum.any?(pages, &(&1.id == entry.id)) do
        Enum.map(pages, fn page -> if page.id == entry.id, do: entry, else: page end)
      else
        [entry | pages]
      end
    end
  end
end
