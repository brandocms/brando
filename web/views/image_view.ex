defmodule Brando.Admin.ImageView do
  @moduledoc """
  View for the Brando Images module.
  """
  use Brando.Web, :view

  def render("delete_selected.json", assigns) do
    %{status: "200", ids: assigns[:ids]}
  end

  use Linguist.Vocabulary

  locale "en", [
    actions: [
      index: "Index - images",
      new: "New image",
      show: "Show image",
      sort: "Sort images",
      edit: "Edit image",
      delete: "Delete image",
      delete_plural: "Delete images",
      empty: "No images",
      upload: "Upload images"
    ]
  ]

  locale "no", [
    actions: [
      index: "Oversikt - bilder",
      new: "Opprett bilde",
      show: "Vis bilde",
      sort: "Sortér bilder",
      edit: "Endre bilde",
      delete: "Slett bilde",
      delete_plural: "Slett bilder",
      empty: "Ingen bilder",
      upload: "Last opp bilder"
    ]
  ]
end
