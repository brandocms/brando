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

  A module that blocks use can't be deleted: its dialog says so instead,
  naming the entries to change first, and offers no Delete.
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

  A module in use gives `%{title, html, refused: true}` instead.

  A page with fragments adds `choice`: a radio group the dialog shows under
  the message, with a page select in its move option, whose values go with
  the delete event.

  The source of synchronized translations lists them and adds a choice of
  what becomes of them (`translations`: `delete`, `transfer` with
  `translations_source`, or `detach`), and `values`, which go with the event
  too: `translations_group`, the group as shown
  (`Brando.Translations.source_group/2`). Two choices come as a list. With
  no choice the viewer may take, the dialog is `refused`.
  """
  def describe(schema, entry) do
    case Brando.Content.guard_delete(schema, entry) do
      {:error, :module_in_use} -> module_in_use(schema, entry)
      :ok -> deletable(schema, entry)
    end
  end

  defp deletable(schema, entry) do
    singular = schema |> Blueprint.get_singular() |> String.downcase()
    name = entry_name(schema, entry)
    owned = owned_counts(schema, entry)

    description = %{
      title: gettext("Delete %{singular}?", singular: singular),
      html: message(schema, name, owned) <> submissions(schema, entry) <> usage(schema, entry),
      confirm: gettext("Delete"),
      cancel: gettext("Cancel")
    }

    description
    |> with_fragments(schema, entry)
    |> with_translations(schema, entry)
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

  # The source of synchronized translations: they are listed, and the
  # dialog asks whether they go with it or stay (`Brando.Translations`'s
  # `delete_with_translations/5` and `delete_keeping_translations/6`). Only
  # the versions the viewer may read are named; the others are counted, and
  # an option is offered only when the viewer may do it to every version it
  # changes.
  defp with_translations(description, schema, entry) do
    case Brando.Translations.source_group(schema, entry.id) do
      nil -> description
      group -> translations_choice(description, schema, group)
    end
  end

  defp translations_choice(description, schema, group) do
    readable = readable_ids(schema, Enum.map(group.translations ++ group.independent, & &1.entry.id))
    {shown, hidden} = Enum.split_with(group.translations, &MapSet.member?(readable, &1.entry.id))
    independent = Enum.filter(group.independent, &MapSet.member?(readable, &1.entry.id))
    delete = delete_option(schema, group, hidden)
    options = Enum.filter([delete, transfer_option(group, shown), detach_option(group)], & &1)
    html = translation_lists(shown, length(hidden), independent) <> translations_note(delete, options, hidden)

    case options do
      [] ->
        %{title: description.title, html: description.html <> html, refused: true}

      options ->
        choice = %{name: "translations", legend: gettext("Its translations"), options: check_first(options)}

        description
        |> Map.update!(:html, &(&1 <> html))
        |> Map.update(:choice, choice, &[&1, choice])
        |> Map.put(:values, %{translations_group: group.fingerprint})
    end
  end

  defp readable_ids(schema, ids) do
    from(e in schema, where: e.id in ^ids, select: e.id)
    |> Boundary.query(schema)
    |> Brando.Repo.all()
    |> MapSet.new()
  end

  # Every translation is seen and may be deleted: published, it may be
  # published too, as the delete asks. Those in the trash stay there.
  defp delete_option(schema, group, []) do
    live = Enum.reject(group.translations, & &1.in_trash)

    if Enum.all?(live, &may_delete?/1), do: Map.merge(%{value: "delete", checked: false}, delete_text(schema, live))
  end

  defp delete_option(_schema, _group, _hidden), do: nil

  # Every translation in the trash already: they stay there, in the group
  defp delete_text(_schema, []),
    do: %{
      label: gettext("Leave them in the trash"),
      hint: gettext("They keep their place in the group, and can be restored once it is.")
    }

  defp delete_text(schema, _live) do
    %{
      label: gettext("Delete them with it"),
      hint:
        if(schema.has_trait(SoftDelete),
          do: gettext("They are moved to the trash with it, and come back when it is restored."),
          else: gettext("They are deleted with it. This can't be undone.")
        )
    }
  end

  defp may_delete?(%{entry: entry, published: published}),
    do: allowed?(:delete, entry) and (not published or allowed?(:publish, entry))

  # A translation the viewer may update becomes the source, which takes the
  # right to update this one too; those in the trash are made independent
  defp transfer_option(group, shown) do
    successors = for %{in_trash: false, entry: entry} = row <- shown, allowed?(:update, entry), do: row

    if successors != [] and allowed?(:update, group.source.entry) and trashed_may_update?(group) do
      %{
        value: "transfer",
        label: gettext("Keep them, and make this one the source:"),
        hint: if(length(group.translations) > 1, do: gettext("The other translations follow it.")),
        checked: false,
        select: %{
          name: "translations_source",
          label: gettext("New source"),
          selected: to_string(hd(successors).entry.id),
          options: Enum.map(successors, &%{value: to_string(&1.entry.id), label: version_label(&1)})
        }
      }
    end
  end

  defp detach_option(group) do
    if Enum.all?(group.translations, &allowed?(:update, &1.entry)) do
      %{
        value: "detach",
        label: gettext("Keep them as independent entries"),
        hint: gettext("They keep their content, and no longer follow a source."),
        checked: false
      }
    end
  end

  defp trashed_may_update?(group),
    do: group.translations |> Enum.filter(& &1.in_trash) |> Enum.all?(&allowed?(:update, &1.entry))

  defp allowed?(action, entry), do: BrandoAdmin.Authorization.allowed?(action, entry)

  # Drafts, then the published ones apart (deleting them takes pages off the
  # site), those in the trash, and the independent versions, which stay
  defp translation_lists(shown, hidden, independent) do
    {trashed, live} = Enum.split_with(shown, & &1.in_trash)
    {published, drafts} = Enum.split_with(live, & &1.published)

    hidden_line =
      if hidden > 0,
        do:
          ~s(<div class="admin-dialog-section"><p>) <>
            ngettext(
              "It has one more translation you may not see.",
              "It has %{count} more translations you may not see.",
              hidden
            ) <> "</p></div>",
        else: ""

    version_list(drafts, gettext("It is the source of these translations:")) <>
      version_list(
        published,
        ngettext(
          "This translation is published: deleting it takes it off the site.",
          "These translations are published: deleting them takes them off the site.",
          length(published)
        )
      ) <>
      hidden_line <>
      version_list(
        trashed,
        ngettext(
          "This translation is in the trash already. It stays there, and becomes an independent entry if the translations are kept.",
          "These translations are in the trash already. They stay there, and become independent entries if the translations are kept.",
          length(trashed)
        )
      ) <>
      version_list(
        independent,
        ngettext(
          "This language version is independent, and stays as it is:",
          "These language versions are independent, and stay as they are:",
          length(independent)
        )
      )
  end

  defp version_list([], _intro), do: ""

  defp version_list(rows, intro) do
    items = Enum.map_join(rows, &version_item/1)
    ~s(<div class="admin-dialog-section"><p>#{escape(intro)}</p><ul class="admin-dialog-list">#{items}</ul></div>)
  end

  defp version_item(%{entry: %schema{} = entry} = row) do
    meta = Enum.join(["[#{language(row.language)}]" | status(entry)], " ")

    case entry_name(schema, entry) do
      nil -> ~s(<li>#{escape(meta)}</li>)
      name -> ~s(<li><strong>#{escape(name)}</strong> <span class="admin-dialog-meta">#{escape(meta)}</span></li>)
    end
  end

  defp version_label(%{entry: %schema{} = entry} = row),
    do: Enum.join(["[#{language(row.language)}]", entry_name(schema, entry) || "##{entry.id}"], " ")

  defp status(%{status: status}) when not is_nil(status),
    do: [BrandoAdmin.Components.Content.List.Row.status_label(status)]

  defp status(_entry), do: []

  # Why the translations can't go with it, when they can stay
  defp translations_note(nil, [_ | _], hidden) do
    text =
      if hidden == [],
        do: gettext("You may not delete every translation, so they can't be deleted with it."),
        else: gettext("You can't see every translation, so they can't be deleted with it.")

    ~s(<div class="admin-dialog-section"><p>#{text}</p></div>)
  end

  defp translations_note(_delete, [], _hidden),
    do:
      ~s(<div class="admin-dialog-section"><p>) <>
        gettext(
          "You may neither delete its translations nor change them so they stay without it, so it can't be deleted."
        ) <> "</p></div>"

  defp translations_note(_delete, _options, _hidden), do: ""

  @doc """
  Why a delete with the source of synchronized translations stopped at one of
  them: the translation by language and name when the viewer may read it,
  and `reason`, as text.
  """
  def translation_refused(schema, entry, reason),
    do:
      gettext("Nothing was deleted: %{translation} was not changed.", translation: translation_name(schema, entry)) <>
        " " <> reason

  @doc "Why a restore of the source of synchronized translations stopped at one of them, as text."
  def restore_refused(schema, entry, reason),
    do:
      gettext("Nothing was restored: %{translation} could not be restored with it.",
        translation: translation_name(schema, entry)
      ) <> " " <> reason

  @doc "Why a synchronized translation is not restored on its own, as text."
  def source_in_trash(schema, source) do
    case named(schema, source) do
      nil ->
        gettext("Not restored: its source is in the trash. Restore the source, and its translations come back with it.")

      name ->
        gettext(
          "Not restored: its source %{source} is in the trash. Restore the source, and its translations come back with it.",
          source: name
        )
    end
  end

  @doc """
  Why a page was not deleted with its fragments: the fragments that are the
  source of synchronized translations, and those translations, by name where
  the viewer may read them. Text.
  """
  def synchronized_fragments_message(page_id) do
    sources =
      for fragment <- Brando.Repo.all(from f in Fragment, where: f.page_id == ^page_id and is_nil(f.deleted_at)),
          group = Brando.Translations.source_group(Fragment, fragment.id),
          do: {fragment, group}

    named_sources =
      for {fragment, group} <- sources, name = named(Fragment, fragment) do
        translations =
          for %{entry: entry} <- group.translations, name = named(Fragment, entry), do: name

        case translations do
          [] ->
            name

          names ->
            gettext("%{fragment} (translated as %{translations})", fragment: name, translations: to_sentence(names))
        end
      end

    case named_sources do
      [] ->
        gettext(
          "Nothing was deleted: a fragment of this page is the source of synchronized translations. Delete the fragment from its own row to choose what becomes of them, or move the fragments."
        )

      names ->
        ngettext(
          "Nothing was deleted: the fragment %{fragments} is the source of synchronized translations. Delete it from its own row to choose what becomes of them, or move the fragments.",
          "Nothing was deleted: the fragments %{fragments} are the source of synchronized translations. Delete them from their own rows to choose what becomes of them, or move the fragments.",
          length(names),
          fragments: to_sentence(names)
        )
    end
  end

  defp translation_name(schema, entry), do: named(schema, entry) || gettext("a translation you may not see")

  # “Name” [EN], when the viewer may read the entry
  defp named(schema, entry) do
    if MapSet.member?(readable_ids(schema, [entry.id]), entry.id) do
      language = if lang = Map.get(entry, :language), do: " [#{language(lang)}]", else: ""
      "“#{entry_name(schema, entry) || "##{entry.id}"}”#{language}"
    end
  end

  # A module blocks use can't go to the trash (`Brando.Content.guard_delete/2`):
  # `refused` makes the dialog a warning with no Delete, naming the entries
  # to change first.
  defp module_in_use(schema, module) do
    subject =
      case entry_name(schema, module) do
        nil -> gettext("This module")
        name -> "<strong>#{escape(name)}</strong>"
      end

    {usages, hidden} = module |> Brando.Content.list_entries_using_module() |> Usage.describe() |> Usage.split()
    count = length(usages) + hidden
    # The same page in two languages has one title
    usages = Enum.map(usages, &with_language/1)

    in_use =
      case usages do
        [] ->
          ngettext(
            "%{module} is used by blocks in one entry, so it can't be deleted.",
            "%{module} is used by blocks in %{count} entries, so it can't be deleted.",
            count,
            module: subject
          )

        usages ->
          ngettext(
            "%{module} is used by blocks in one entry, so it can't be deleted: %{places}.",
            "%{module} is used by blocks in %{count} entries, so it can't be deleted: %{places}.",
            count,
            module: subject,
            places: to_sentence(place_links(usages, hidden))
          )
      end

    %{
      title: gettext("Module in use"),
      html: in_use <> " " <> gettext("Take its blocks out of these entries, or move them to the trash, first."),
      refused: true
    }
  end

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
        " " <>
          ngettext(
            "It is used in one place: %{places}.",
            "It is used in %{count} places: %{places}.",
            length(usages) + hidden,
            places: to_sentence(place_links(usages, hidden))
          )
    end
  end

  defp with_language(%{language: language, label: label} = usage) when not is_nil(language),
    do: %{usage | label: "#{label} [#{language |> to_string() |> String.upcase()}]"}

  defp with_language(usage), do: usage

  # The first few places, linked where they have an admin page, and a count
  # of the rest
  defp place_links(usages, hidden) do
    shown = Enum.take(usages, @usage_shown)
    rest = length(usages) - length(shown) + hidden

    links =
      Enum.map(shown, fn
        %{url: url, label: label} when is_binary(url) ->
          ~s(<a href="#{escape(url)}" target="_blank">#{escape(label)}</a>)

        %{label: label} ->
          escape(label)
      end)

    if rest > 0, do: links ++ [gettext("%{count} more", count: rest)], else: links
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

  @doc "The entry's title as its identifier gives it, as text; nil without one."
  def entry_name(schema, entry) do
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
