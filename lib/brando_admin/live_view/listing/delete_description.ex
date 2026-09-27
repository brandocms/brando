defmodule BrandoAdmin.LiveView.Listing.DeleteDescription do
  @moduledoc """
  The text of a listing's delete dialog: the entry by name, what goes with
  it, and whether it can be brought back.

  "What goes with it" is the rows the entry owns — its `has_many` relations
  with `cast: true`, the ones its form edits as part of it (a project's
  artworks and links). Deleting the entry deletes them.
  """
  use Gettext, backend: Brando.Gettext

  alias Brando.Blueprint
  alias Brando.Blueprint.Relations
  alias Brando.Trait.SoftDelete

  @doc """
  `%{title, message, confirm, cancel}` for deleting `entry`. The message is
  HTML (the dialog renders HTML), with the entry's name escaped.
  """
  def describe(schema, entry) do
    singular = schema |> Blueprint.get_singular() |> String.downcase()
    name = entry_name(schema, entry)
    owned = owned_counts(schema, entry)

    %{
      title: gettext("Delete %{singular}?", singular: singular),
      message: message(schema, singular, name, owned),
      confirm: gettext("Delete"),
      cancel: gettext("Cancel")
    }
  end

  defp message(schema, singular, name, owned) do
    subject =
      if name,
        do: "<strong>#{escape(name)}</strong>",
        else: gettext("This %{singular}", singular: singular)

    if schema.has_trait(SoftDelete) do
      # Soft deleted, the owned rows stay with the entry and come back with it.
      with_it = owned != [] && gettext("with its %{children}", children: to_sentence(owned))

      [subject, gettext("is moved to the list's Deleted filter"), with_it]
      |> sentence()
      |> Kernel.<>(" " <> gettext("It can be restored from there."))
    else
      with_it = owned != [] && gettext("together with %{children}", children: to_sentence(owned))

      [subject, gettext("will be deleted"), with_it]
      |> sentence()
      |> Kernel.<>(" " <> gettext("This can't be undone."))
    end
  end

  defp sentence(parts), do: (parts |> Enum.reject(&(&1 in [nil, false])) |> Enum.join(" ")) <> "."

  defp entry_name(schema, entry) do
    if function_exported?(schema, :__has_identifier__, 0) and schema.__has_identifier__() do
      case schema.__identifier__(entry) do
        %{title: title} when is_binary(title) and title != "" -> title
        _ -> nil
      end
    end
  rescue
    _ -> nil
  end

  defp owned_counts(schema, entry) do
    for %{type: :has_many, name: name, opts: %{cast: true, module: module}} <- Relations.__relations__(schema),
        count = Brando.Repo.aggregate(Ecto.assoc(entry, name), :count),
        count > 0 do
      label =
        if count == 1,
          do: Blueprint.get_singular(module),
          else: Blueprint.get_plural(module)

      "#{count} #{label |> String.downcase() |> String.replace("_", " ")}"
    end
  end

  defp to_sentence([one]), do: one
  defp to_sentence(items), do: Enum.join(Enum.drop(items, -1), ", ") <> " " <> gettext("and") <> " " <> List.last(items)

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
