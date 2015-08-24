defmodule <%= admin_module %>View do
  use Brando.Web, :view
  use Linguist.Vocabulary
  alias <%= admin_module %>Form

  locale "en", [
    actions: [
      index: "Index - <%= plural %>",
      new: "New <%= singular %>",
      show: "Show <%= singular %>",
      edit: "Edit <%= singular %>",
      delete: "Delete <%= singular %>"
    ]
  ]

  locale "no", [
    actions: [
      index: "Oversikt - <%= no_plural %>",
      new: "Opprett <%= no_singular %>",
      show: "Vis <%= no_singular %>",
      edit: "Endre <%= no_singular %>",
      delete: "Slett <%= no_singular %>"
    ]
  ]
end
