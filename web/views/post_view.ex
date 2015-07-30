defmodule Brando.Admin.PostView do
  @moduledoc """
  View for the Brando News module.
  """
  use Brando.Web, :view
  use Linguist.Vocabulary
  alias Brando.PostForm

  locale "en", [
    actions: [
      index: "Index - posts",
      new: "New post",
      show: "Show post",
      edit: "Edit post",
      empty: "No posts",
      delete: "Delete post"
    ]
  ]

  locale "no", [
    actions: [
      index: "Oversikt - poster",
      new: "Opprett post",
      show: "Vis post",
      edit: "Endre post",
      empty: "Ingen poster",
      delete: "Slett post"
    ]
  ]
end
