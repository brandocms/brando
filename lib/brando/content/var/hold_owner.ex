defmodule Brando.Content.Var.HoldOwner do
  @moduledoc """
  A var's owner is not taken from params. The schema whose
  `cast_assoc(:vars, …)` builds the var sets its own key when it saves it
  (a page's `page_id`, a global set's `global_set_id`); code that creates a
  var on its own sets the key on the struct: `%Var{page_id: id}`.

  Otherwise a page or table template save, or a proposal creating a var,
  could carry another owner's key: a `global_set_id` adds a global to a set
  its editor may not define, a `module_id` a var to a module's definition.

  Only `Ecto.Changeset` is referenced: `Brando.Content.Var` depends on this
  trait at compile time.
  """
  use Brando.Trait

  alias Ecto.Changeset

  @owners [:page_id, :block_id, :module_id, :table_template_id, :table_row_id, :global_set_id, :menu_item_id]

  def changeset_mutator(_module, _config, changeset, _user, _opts),
    do: Enum.reduce(@owners, changeset, &Changeset.delete_change(&2, &1))
end
