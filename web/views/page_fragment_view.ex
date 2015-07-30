defmodule Brando.Admin.PageFragmentView do
  @moduledoc """
  View for the Brando Pages module.
  """
  use Brando.Web, :view
  alias Brando.PageFragmentForm

  use Linguist.Vocabulary

  locale "en", [
    actions: [
      index: "Index - page fragments",
      new: "New page fragment",
      show: "Show page fragment",
      edit: "Edit page fragment",
      delete: "Delete page fragment",
      empty: "No fragments"
    ]
  ]

  locale "no", [
    actions: [
      index: "Oversikt - sidefragmenter",
      new: "Opprett sidefragment",
      show: "Vis sidefragment",
      edit: "Endre sidefragment",
      delete: "Slett sidefragment",
      empty: "Ingen fragmenter"
    ]
  ]
end
