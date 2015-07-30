defmodule Brando.Admin.UserView do
  @moduledoc """
  View for the Brando Users module.
  """
  use Brando.Web, :view
  alias Brando.UserForm
  alias Brando.UserProfileForm

  use Linguist.Vocabulary

  locale "en", [
    actions: [
      index: "Index - users",
      new: "New user",
      show: "Show user",
      edit: "Edit user",
      profile: "Profile",
      delete: "Delete user"
    ]
  ]

  locale "no", [
    actions: [
      index: "Oversikt - brukere",
      new: "Opprett bruker",
      show: "Vis bruker",
      edit: "Endre bruker",
      profile: "Brukerprofil",
      delete: "Slett bruker"
    ]
  ]
end
