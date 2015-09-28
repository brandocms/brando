defmodule Brando.Admin.ImageCategoryView do
  @moduledoc """
  View for the Brando Images module.
  """
  alias Brando.ImageCategoryForm
  alias Brando.ImageCategoryConfigForm
  use Brando.Web, :view
  use Brando.Sequence, :view
  use Linguist.Vocabulary

  locale "en", [
    actions: [
      index: "Index - image category",
      new: "New image category",
      show: "Show image category",
      sort: "Sort image category",
      configure: "Configure image category",
      store_sort: "Save sorted category",
      upload: "Upload to this image category",
      edit: "Edit image category",
      empty: "No image category",
      delete: "Delete image category",
      existing: "Existing images in this category"
    ]
  ]

  locale "no", [
    actions: [
      index: "Oversikt - bildekategorier",
      new: "Opprett bildekategori",
      show: "Vis bildekategori",
      sort: "Sortér bildekategori",
      configure: "Konfigurér bildekategori",
      store_sort: "Lagre sortert kategori",
      upload: "Last opp til denne bildekategorien",
      edit: "Endre bildekategori",
      empty: "Ingen bildekategorier",
      delete: "Slett bildekategori",
      existing: "Eksisterende bilder i denne kategorien"
    ]
  ]
end
