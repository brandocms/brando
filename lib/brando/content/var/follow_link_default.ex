defmodule Brando.Content.Var.FollowLinkDefault do
  @moduledoc """
  An empty link var opens on the tab its definition chooses.

  `link_default_type` is developer configuration: whether the link dialog of
  a var with no link yet starts on URL or on Content (an entry). The tab the
  dialog shows is the var's own `link_type`, so an empty var takes the default
  as its `link_type`:

    * when it is copied from its definition: a new block from its module, a
      var the module added since, a reset to the module's values, a new table
      row (`put/1`, through `Brando.Content.Blocks.remove_pk_from_vars/1`);
    * when its default changes: a module save syncing its blocks
      (`Brando.Content.Blocks.reapply_vars/3`), or a page, global or module
      var saved with a new default (`follow/1`, as this trait).

  The trait follows on save, not on validate. While the form is open the
  editor's tab is theirs: an unsaved new default rewriting `link_type` on each
  validate would send them back to Content whenever they clicked URL.

  A link that is set keeps its `link_type`, whatever the default says.

  Only `Ecto.Changeset` is referenced: `Brando.Content.Var` depends on this
  trait at compile time, so naming the var schema here would make a
  compile-connected cycle.
  """
  use Brando.Trait

  alias Ecto.Changeset

  def changeset_mutator(_module, _config, changeset, _user, _opts) do
    changeset
    |> store_url_as_empty()
    |> Changeset.prepare_changes(&follow/1)
  end

  # URL is the default, and stored as empty: a field Brando added since a
  # definition was exported must stay empty, or every module file would differ
  # from its lockfile's baseline (`Brando.Content.Definition.Value`).
  defp store_url_as_empty(changeset) do
    if Changeset.get_field(changeset, :link_default_type) == :url,
      do: Changeset.put_change(changeset, :link_default_type, nil),
      else: changeset
  end

  @doc """
  Sets `link_type` to the var's default tab when this changeset changes the
  default and the link is empty.
  """
  @spec follow(Changeset.t()) :: Changeset.t()
  def follow(%Changeset{} = changeset) do
    var = Changeset.apply_changes(changeset)
    default = default_type(var)

    if default != default_type(changeset.data) and empty_link?(var),
      do: Changeset.put_change(changeset, :link_type, default),
      else: changeset
  end

  @doc """
  The copy of an empty link var starts on its default tab.
  """
  @spec put(struct()) :: struct()
  def put(%{type: :link, link_default_type: _} = var) do
    if empty_link?(var), do: %{var | link_type: default_type(var)}, else: var
  end

  def put(var), do: var

  defp default_type(var), do: Map.get(var, :link_default_type) || :url

  @doc "True for a link var with neither a URL nor an entry."
  @spec empty_link?(map()) :: boolean()
  def empty_link?(%{type: :link} = var),
    do: blank?(Map.get(var, :value)) and is_nil(Map.get(var, :identifier_id))

  def empty_link?(_var), do: false

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: false
end
