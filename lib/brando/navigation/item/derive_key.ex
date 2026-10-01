defmodule Brando.Navigation.Item.DeriveKey do
  @moduledoc """
  A menu item's key follows its label until it is set.

  The key is what a template picks an item out by (`item.key == "contact"`),
  a developer's concern the editor shouldn't have to fill in. While it is
  unset (empty, or the old default "key") it is taken from the link: its text,
  or the title of the entry it links to, as `snake_case`. Once set it stays,
  so renaming the item doesn't break a template that uses the key.

  The form renders the derived key in the key field and posts it back, which
  reads exactly like a key the editor typed. So the derived key also goes into
  the virtual `derived_key`, which the form posts back beside it: a key that
  still equals it has not been edited, and follows the link again.
  """
  use Brando.Trait

  import Ecto.Changeset

  # Before `validate_required`, which the key is
  @changeset_phase :before_validate_required

  @unset [nil, "", "key"]

  def changeset_mutator(_module, _config, changeset, _user, _opts) do
    if unset?(changeset) do
      key = derive(get_field(changeset, :link)) || "item"

      changeset
      |> put_change(:key, key)
      |> put_change(:derived_key, key)
    else
      changeset
    end
  end

  defp unset?(changeset) do
    key = get_field(changeset, :key)
    key in @unset or key == get_field(changeset, :derived_key)
  end

  defp derive(%{link_text: text}) when is_binary(text) and text != "", do: to_key(text)

  defp derive(%{identifier_id: id}) when is_integer(id) do
    # Named at runtime, inside the call: `Item` depends on this trait at
    # compile time, so a reference to the repo or the identifier schema (both
    # reach back to `Item`) would make a compile-connected cycle, which CI
    # rejects. A module attribute would still compile to a direct reference.
    repo = Module.concat(["Brando", "Repo"])
    identifier = Module.concat(["Brando", "Content", "Identifier"])

    case repo.get(identifier, id) do
      %{title: title} when is_binary(title) -> title |> String.replace(~r/^\[[^\]]*\]\s*/, "") |> to_key()
      _ -> nil
    end
  end

  defp derive(_link), do: nil

  defp to_key(text) do
    case text |> Slug.slugify() |> to_string() |> String.replace("-", "_") do
      "" -> nil
      key -> key
    end
  end
end
