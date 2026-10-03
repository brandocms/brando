defmodule BrandoAdmin.Components.Form.Input.FormId do
  @moduledoc """
  Resolves the HTML form id that media inputs hand to their pickers and drawers.
  """

  alias Brando.Utils

  @doc """
  Returns `"<singular>_form"` for the schema that owns `form`.

  For a nested form (`page[fragments][0]`) the owner is the parent schema, not
  the struct behind the nested changeset.
  """
  def for_form(form) do
    path = Utils.get_path_from_field_name(form.name)
    module_from_form = form.source.data.__struct__

    module =
      if path == [] do
        module_from_form
      else
        Utils.get_parent_module_from_field_name(form.name, module_from_form)
      end

    "#{module.__naming__().singular}_form"
  end
end
