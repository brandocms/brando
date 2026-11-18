defmodule BrandoAdmin.LiveView.Listing.DeleteDescription do
  @moduledoc """
  The text of a listing's delete dialog: the entry by name, what goes with
  it, and whether it can be brought back.

  "What goes with it" is the rows the entry owns — its `has_many` relations
  with `cast: true`, the ones its form edits as part of it (a project's
  artworks and links). Deleting the entry deletes them.

  Media with usage tracking (`Brando.Content.Usage`: images, videos,
  galleries, files) also says where it is used, linked, so the editor sees
  what the delete takes from. So does a form, in any of its languages: a
  page shows the form in its own language. Deleting is still allowed. A form
  that is the last language of its key says how many submissions go with it.
  """
  use Gettext, backend: Brando.Gettext

  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.Boundary
  alias Brando.Blueprint
  alias Brando.Blueprint.Relations
  alias Brando.Content.Usage
  alias Brando.Pages.Fragment
  alias Brando.Trait.SoftDelete

  @doc """
  `%{title, html, confirm, cancel}` for deleting `entry`. `html` is the
  message as markup (it links the places media is used), with the entry's
  name and every place escaped; the rest is text.

  A page with fragments adds `choice`: a radio group the dialog shows under
  the message, with a page select in its move option, whose values go with
  the delete event.
  """
  def describe(schema, entry) do
    singular = schema |> Blueprint.get_singular() |> String.downcase()
    name = entry_name(schema, entry)
    owned = owned_counts(schema, entry)

    description = %{
      title: gettext("Delete %{singular}?", singular: singular),
      html: message(schema, name, owned) <> submissions(schema, entry) <> usage(schema, entry),
      confirm: gettext("Delete"),
      cancel: gettext("Cancel")
    }

    with_fragments(description, schema, entry)
  end

  # A page's fragments are found by key, not through the page, so they would
  # outlive it on the site: the dialog lists them and asks where they go
  # (`Brando.Pages.delete_page/3`). The choice's values are pushed with the
  # delete event, as `fragments` and `fragments_page`. A choice the viewer may
  # not take is left out.
  #
  # The fragments and pages are those the viewer may read; the others are
  # counted, not named.
  defp with_fragments(description, Brando.Pages.Page, %{deleted_at: nil} = page) do
    query =
      from(f in Fragment,
        where: f.page_id == ^page.id and is_nil(f.deleted_at),
        order_by: [asc: f.sequence, asc: f.key, asc: f.id]
      )

    case Brando.Repo.aggregate(query, :count) do
      0 ->
        description

      count ->
        fragments = query |> Boundary.query(Fragment) |> Brando.Repo.all()
        options = fragment_options(page)

        description
        |> Map.update!(:html, &(&1 <> fragment_list(fragments, count) <> refused(options)))
        |> Map.put(:choice, %{name: "fragments", legend: gettext("Its fragments"), options: options})
    end
  end

  defp with_fragments(description, _schema, _entry), do: description

  defp fragment_options(page) do
    [
      BrandoAdmin.Authorization.allowed?(:update, Fragment) && move_option(page),
      BrandoAdmin.Authorization.allowed?(:delete, Fragment) &&
        %{
          value: "delete",
          label: gettext("Delete them with the page"),
          hint: gettext("They are moved to the trash, and come back if the page is restored."),
          checked: false
        }
    ]
    |> Enum.filter(& &1)
    |> check_first()
  end

  defp move_option(page) do
    target = Brando.Pages.fragment_target(page)

    pages =
      from(p in Brando.Pages.Page,
        where: is_nil(p.deleted_at) and p.id != ^page.id,
        order_by: [asc: p.language, asc: p.title, asc: p.id],
        select: %{id: p.id, title: p.title, language: p.language}
      )
      |> Boundary.query(Brando.Pages.Page)
      |> Brando.Repo.all()

    # A default the viewer may not read is not chosen for them
    selected = if target && Enum.any?(pages, &(&1.id == target.id)), do: to_string(target.id), else: ""

    %{
      value: "move",
      label: gettext("Move them to"),
      hint: gettext("They stay on the site. With no page, they are listed under Fragments without a page."),
      checked: true,
      select: %{
        name: "fragments_page",
        label: gettext("Page"),
        selected: selected,
        options: [
          %{value: "", label: gettext("No page")}
          | Enum.map(pages, &%{value: to_string(&1.id), label: "[#{language(&1.language)}] #{&1.title}"})
        ]
      }
    }
  end

  defp check_first([first | rest]), do: [%{first | checked: true} | Enum.map(rest, &%{&1 | checked: false})]
  defp check_first([]), do: []

  defp refused([]),
    do:
      ~s(<div class="admin-dialog-section"><p>) <>
        gettext("You may not move or delete these fragments, so the page can't be deleted.") <> "</p></div>"

  defp refused(_options), do: ""

  defp fragment_list(fragments, count) do
    items =
      Enum.map_join(fragments, fn fragment ->
        key = "#{fragment.parent_key}/#{fragment.key}"
        lang = "[#{language(fragment.language)}]"

        case fragment.title do
          title when is_binary(title) and title != "" ->
            ~s(<li><strong>#{escape(title)}</strong> <span class="admin-dialog-meta">#{escape(key)} #{lang}</span></li>)

          _ ->
            ~s(<li>#{escape(key)} <span class="admin-dialog-meta">#{lang}</span></li>)
        end
      end)

    hidden = count - length(fragments)

    items =
      if hidden > 0,
        do: items <> "<li>" <> ngettext("One more you may not see", "%{count} more you may not see", hidden) <> "</li>",
        else: items

    ~s(<div class="admin-dialog-section"><p>) <>
      ngettext(
        "It has a fragment, which templates find by its key:",
        "It has %{count} fragments, which templates find by their keys:",
        count
      ) <> ~s(</p><ul class="admin-dialog-list">#{items}</ul></div>)
  end

  defp language(language), do: language |> to_string() |> String.upcase() |> escape()

  # Without a name the subject is "This entry": splicing the schema's noun
  # into "This %{singular}" cannot agree with its gender ("Denne bilde").
  defp message(schema, name, owned) do
    subject = if name, do: "<strong>#{escape(name)}</strong>", else: gettext("This entry")

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

  defp submissions(Brando.Forms.Form, %{key: key}) do
    with [_last_language] <- Brando.Forms.list_forms_by_key(key),
         count when count > 0 <- Brando.Forms.count_submissions_going_with_form(key) do
      " " <>
        ngettext("Its submission is deleted with it.", "Its %{count} submissions are deleted with it.", count)
    else
      _ -> ""
    end
  end

  defp submissions(_schema, _entry), do: ""

  @usage_kinds %{
    Module.concat(["Brando", "Images", "Image"]) => :image,
    Module.concat(["Brando", "Videos", "Video"]) => :video,
    Module.concat(["Brando", "Galleries", "Gallery"]) => :gallery,
    Module.concat(["Brando", "Files", "File"]) => :file
  }

  # A long list is cut: the dialog names the first few and counts the rest,
  # with the places the viewer may not read, which it never names.
  @usage_shown 5

  defp usage(schema, entry) do
    case schema |> usages(entry) |> Usage.split() do
      {[], 0} ->
        ""

      {[], hidden} ->
        " " <> ngettext("It is used in one place.", "It is used in %{count} places.", hidden)

      {usages, hidden} ->
        shown = Enum.take(usages, @usage_shown)
        rest = length(usages) - length(shown) + hidden

        links =
          Enum.map(shown, fn
            %{url: url, label: label} when is_binary(url) ->
              ~s(<a href="#{escape(url)}" target="_blank">#{escape(label)}</a>)

            %{label: label} ->
              escape(label)
          end)

        links = if rest > 0, do: links ++ [gettext("%{count} more", count: rest)], else: links

        " " <>
          ngettext(
            "It is used in one place: %{places}.",
            "It is used in %{count} places: %{places}.",
            length(usages) + hidden,
            places: to_sentence(links)
          )
    end
  end

  defp usages(Brando.Forms.Form, %{key: key}), do: Brando.Forms.list_usage(key)

  defp usages(schema, %{id: id}) do
    case Map.get(@usage_kinds, schema) do
      nil -> []
      kind -> Map.get(Usage.list(kind, [id]), id, [])
    end
  end

  defp usages(_schema, _entry), do: []

  defp sentence(parts), do: (parts |> Enum.reject(&(&1 in [nil, false])) |> Enum.join(" ")) <> "."

  defp entry_name(schema, entry) do
    if function_exported?(schema, :__has_identifier__, 0) and schema.__has_identifier__() do
      case schema.__identifier__(entry) do
        %{title: title} when is_binary(title) and title != "" -> Brando.Content.Identifier.title_text(schema, title)
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

  defp to_sentence(items) do
    {rest, [last]} = Enum.split(items, -1)
    Enum.join(rest, ", ") <> " " <> gettext("and") <> " " <> last
  end

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
