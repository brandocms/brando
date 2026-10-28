defmodule Brando.Content.Var.SanitizeRichText do
  @moduledoc """
  A `rich_text` var's value is stored sanitized, as a text block's text is
  (`Brando.RichText.validate_fields/2`): a value with unsafe markup or a link
  with an unsupported address is refused.

  As a trait it covers vars saved with their owner (pages, global sets,
  modules, table templates); block vars run `sanitize/1` in
  `Brando.Content.Block.var_changeset/3,4`.

  Only `Ecto.Changeset` is referenced: `Brando.Content.Var` depends on this
  trait at compile time.
  """
  use Brando.Trait

  alias Ecto.Changeset

  # `sanitize_rich_text: false` skips it, for re-reading records already
  # stored: one value saved before must not stop a definitions snapshot.
  def changeset_mutator(_module, _config, changeset, _user, opts) do
    if opts[:sanitize_rich_text] == false, do: changeset, else: sanitize(changeset)
  end

  @doc "Sanitizes the changed value of a `rich_text` var."
  @spec sanitize(Changeset.t()) :: Changeset.t()
  def sanitize(changeset) do
    if Changeset.get_field(changeset, :type) == :rich_text,
      do: Brando.RichText.validate_fields(changeset, [:value]),
      else: changeset
  end
end
