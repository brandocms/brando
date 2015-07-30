defmodule Brando.Admin.ImageSeriesView do
  @moduledoc """
  View for the Brando Images module.
  """
  alias Brando.ImageSeriesForm
  use Brando.Web, :view
  use Brando.Sequence, :view

  def render("upload_post.json", _assigns) do
    %{status: "200"}
  end

  use Linguist.Vocabulary

  locale "en", [
    actions: [
      index: "Index - image series",
      new: "New image series",
      show: "Show image series",
      sort: "Sort image series",
      store_sort: "Save sorted series",
      upload: "Upload to this image series",
      edit: "Edit image series",
      empty: "No image series",
      delete: "Delete image series",
      existing: "Existing images in this series"
    ]
  ]

  locale "no", [
    actions: [
      index: "Oversikt - bildeserier",
      new: "Opprett bildeserie",
      show: "Vis bildeserie",
      sort: "Sortér bildeserie",
      store_sort: "Lagre sortert serie",
      upload: "Last opp til denne bildeserien",
      edit: "Endre bildeserie",
      empty: "Ingen bildeserier",
      delete: "Slett bildeserie",
      existing: "Eksisterende bilder i denne serien"
    ]
  ]
end
