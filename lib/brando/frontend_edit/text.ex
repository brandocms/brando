defmodule Brando.FrontendEdit.Text do
  @moduledoc false
  # The overlay's copy, translated into the admin's language before the page
  # is sent. The frontend script has no Gettext of its own.
  use Gettext, backend: Brando.Gettext

  def strings do
    %{
      editPage: pgettext("frontend edit", "Edit page"),
      editing: gettext("Editing"),
      done: gettext("Done"),
      hint: gettext("Click a block to edit it"),
      emptyHint: gettext("This page has no blocks to edit here"),
      shared: gettext("Shared fragment"),
      notAllowed: gettext("You can’t edit this"),
      close: gettext("Close editor"),
      loading: gettext("Opening editor…"),
      unsavedTitle: gettext("Unsaved changes"),
      unsavedBody: gettext("Save your changes before you leave this block?"),
      save: gettext("Save"),
      discard: gettext("Discard changes"),
      keepEditing: gettext("Keep editing"),
      saved: gettext("Saved"),
      block: gettext("Block")
    }
  end
end
