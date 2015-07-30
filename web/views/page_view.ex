defmodule Brando.Admin.PageView do
  @moduledoc """
  View for the Brando Pages module.
  """
  use Brando.Web, :view
  alias Brando.PageForm

  use Linguist.Vocabulary

  locale "en", [
    actions: [
      index: "Index - pages",
      new: "New page",
      show: "Show page",
      edit: "Edit page",
      delete: "Delete page"
    ]
  ]

  locale "no", [
    actions: [
      index: "Oversikt - sider",
      new: "Opprett side",
      show: "Vis side",
      edit: "Endre side",
      delete: "Slett side"
    ]
  ]
end
