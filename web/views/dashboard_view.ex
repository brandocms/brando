defmodule Brando.Admin.DashboardView do
  @moduledoc """
  View for the Brando Dashboard module.
  """
  use Brando.Web, :view
  use Linguist.Vocabulary

  locale "en", [
    go_to_frontend: "Go to frontend website >>"
  ]

  locale "no", [
    go_to_frontend: "Gå til frontend nettside >>"
  ]
end
