defmodule BrandoAdmin.LiveView.Listing.Hooks do
  @moduledoc """
  Runtime hooks for the public `BrandoAdmin.LiveView.Listing` entry point.
  """
  use Gettext, backend: Brando.Gettext

  import Phoenix.Component
  import Phoenix.LiveView

  alias Brando.Utils

  require Logger

  def hooks(_params, _session, socket, schema, overrides \\ []) do
    if Phoenix.LiveView.connected?(socket) do
      subscribe(schema)
    end

    socket =
      socket
      |> assign(:socket_connected, true)
      # The layout marks its container so the listing stylesheet can key on a
      # class rather than `:has(> .content-list-wrapper)` on that container —
      # which sits above the block editor, so every DOM mutation in an entry
      # form would pay for re-evaluating it. A schema-less
      # listing is a dashboard, which renders no list and takes no treatment.
      |> assign(:admin_workspace?, not is_nil(schema))
      |> set_admin_locale()
      |> assign_schema(schema)
      |> assign_create_url(schema)
      |> assign_title()
      |> assign_page_icon()
      |> attach_hooks(schema, overrides)

    {:cont, socket}
  end

  @doc """
  Runs a listing event held by `BrandoAdmin.Reauth` once the session has
  confirmed: the listing's own events here, the view's (`{:cont, socket}`)
  in its `handle_event/3`.
  """
  def replay_event(_event, _params, socket, nil, _overrides), do: {:cont, socket}
  def replay_event(event, params, socket, schema, overrides), do: listing_event(event, params, socket, schema, overrides)

  defp attach_hooks(socket, nil, _overrides) do
    attach_listing_info_hooks(socket, nil)
  end

  defp attach_hooks(socket, schema, overrides) do
    socket
    |> attach_hook(:b_listing_events, :handle_event, &listing_event(&1, &2, &3, schema, overrides))
    |> attach_listing_info_hooks(schema)
  end

  @doc """
  Whether a listing view with these `overrides` deletes entries permanently
  from the trash: not one with a delete of its own (the user listing). Its
  menus offer Delete permanently only then.
  """
  def deletes_permanently?(overrides), do: "delete_entry" not in overrides

  # Events the view handles itself (the `overrides` option) pass on to it
  defp listing_event(event, params, socket, schema, overrides) do
    cond do
      event in overrides ->
        {:cont, socket}

      event in ~w(delete_entry_permanently delete_selected_permanently) and not deletes_permanently?(overrides) ->
        delete_refused(gettext("This list does not delete entries permanently. Nothing was deleted."))
        {:halt, socket}

      true ->
        handle_listing_event(event, params, socket, schema)
    end
  end

  defp handle_listing_event(
         "set_status",
         %{"id" => id, "status" => status, "schema" => target_schema},
         socket,
         schema
       ) do
    if target_schema = Brando.Authorization.Catalog.schema(target_schema) do
      Brando.Trait.Status.update_status(target_schema, id, status, socket.assigns.current_user)
      update_list_entries(schema)
    end

    {:halt, socket}
  end

  defp handle_listing_event("edit_entry", %{"id" => id}, socket, schema) do
    update_url = schema.__admin_route__(:update, [id])
    {:halt, push_navigate(socket, to: update_url)}
  end

  defp handle_listing_event("undelete_entry", %{"id" => entry_id}, socket, schema) do
    singular = schema.__naming__().singular
    context = schema.__modules__().context
    translated_singular = translated_singular(schema)

    with {:ok, entry} <- apply(context, :"get_#{singular}", [entry_id]),
         {:ok, _restored} <- Brando.Authorization.Boundary.restore(socket.assigns.current_user, entry) do
      send(
        self(),
        {:toast, "#{String.capitalize(translated_singular)} #{gettext("undeleted")}"}
      )

      update_list_entries(schema)
    else
      {:error, {:recorded_here, live}} ->
        send(self(), {:toast, Brando.Videos.restore_refused_message(live)})

      {:error, {:source_in_trash, source}} ->
        delete_refused(BrandoAdmin.LiveView.Listing.DeleteDescription.source_in_trash(schema, source))

      {:error, {:translation, translation, reason}} ->
        message =
          BrandoAdmin.LiveView.Listing.DeleteDescription.restore_refused(schema, translation, translation_reason(reason))

        delete_refused(message)

      {:error, _error} ->
        send(
          self(),
          {:toast, "#{gettext("Error undeleting")} #{String.capitalize(translated_singular)}"}
        )
    end

    {:halt, socket}
  end

  # The delete dialog's text, asked for by the ConfirmClick hook before it
  # opens: the entry by name and what's deleted with it.
  defp handle_listing_event("describe_delete", %{"id" => entry_id}, socket, schema) do
    singular = schema.__naming__().singular
    context = schema.__modules__().context

    reply =
      case apply(context, :"get_#{singular}", [%{matches: %{id: entry_id}}]) do
        {:ok, entry} -> BrandoAdmin.LiveView.Listing.DeleteDescription.describe(schema, entry)
        _ -> %{}
      end

    {:halt, reply, socket}
  end

  # The source of synchronized translations, as its dialog chose
  # (`DeleteDescription`): deleted with them, or keeping them. A group that
  # changed since the dialog showed it opens the dialog again (`opener`).
  defp handle_listing_event(
         "delete_entry",
         %{"id" => entry_id, "translations" => choice} = params,
         %{assigns: %{current_user: user}} = socket,
         schema
       ) do
    case delete_source(schema, entry_id, choice, params, user) do
      {:ok, %{translations: []}} ->
        send(self(), {:toast, "#{String.capitalize(translated_singular(schema))} #{gettext("deleted")}"})
        update_list_entries(schema)
        {:halt, socket}

      {:ok, %{translations: translations}} ->
        message =
          ngettext("%{entry} deleted, with its translation", "%{entry} deleted, with its %{count} translations",
            length(translations),
            entry: String.capitalize(translated_singular(schema))
          )

        send(self(), {:toast, message})
        update_list_entries(schema)
        {:halt, socket}

      {:error, :group_changed} ->
        delete_refused(gettext("Nothing was deleted: its translations changed since the dialog opened. Check them again."))
        update_list_entries(schema)
        {:halt, push_event(socket, "b:confirm-click-again", %{id: params["opener"]})}

      {:error, reason} ->
        delete_refused(delete_error_message(schema, entry_id, reason))
        {:halt, socket}
    end
  end

  defp handle_listing_event(
         "delete_entry",
         %{"id" => entry_id} = params,
         %{assigns: %{current_user: user}} = socket,
         schema
       ) do
    if {:before_delete, 3} in schema.__info__(:functions) do
      schema.before_delete(entry_id, socket, self())
    end

    singular = schema.__naming__().singular
    context = schema.__modules__().context

    case apply(context, :"delete_#{singular}", [entry_id, user | delete_opts(schema, params)]) do
      {:ok, _} ->
        send(self(), {:toast, "#{String.capitalize(translated_singular(schema))} #{gettext("deleted")}"})
        update_list_entries(schema)

      {:error, reason} ->
        delete_refused(delete_error_message(schema, entry_id, reason))
    end

    {:halt, socket}
  end

  # Delete permanently, in the trash: the row goes only if it is still in the
  # trash as the menu showed it (`deleted_at`)
  defp handle_listing_event(
         "delete_entry_permanently",
         %{"id" => entry_id, "deleted_at" => deleted_at},
         %{assigns: %{current_user: user}} = socket,
         schema
       ) do
    case purge_entry(schema, entry_id, deleted_at, user) do
      :ok ->
        send(self(), {:toast, "#{String.capitalize(translated_singular(schema))} #{gettext("deleted permanently")}"})
        update_list_entries(schema)

      {:error, reason} ->
        delete_refused(gettext("Not deleted.") <> " " <> purge_error_message(reason, 1))
    end

    {:halt, socket}
  end

  defp handle_listing_event(
         "delete_selected",
         %{"ids" => ids},
         %{assigns: %{current_user: user, schema: schema}} = socket,
         _listing_schema
       ) do
    singular = schema.__naming__().singular
    context = schema.__modules__().context

    for entry_id <- Jason.decode!(ids) do
      with {:error, reason} <- apply(context, :"delete_#{singular}", [entry_id, user]),
           do: delete_refused(delete_error_message(schema, entry_id, reason))
    end

    update_list_entries(schema)

    {:halt, socket}
  end

  # Delete permanently for a selection in the trash: each row as
  # `delete_entry_permanently` deletes it, in a transaction of its own
  defp handle_listing_event(
         "delete_selected_permanently",
         %{"entries" => entries},
         %{assigns: %{current_user: user, schema: schema}} = socket,
         _listing_schema
       ) do
    entries = for %{"id" => id} = entry <- Jason.decode!(entries), do: {id, entry["deleted_at"]}
    names = entry_names(schema, Enum.map(entries, &elem(&1, 0)))

    {deleted, refused} =
      entries
      |> Enum.map(fn {id, deleted_at} -> {id, purge_entry(schema, id, deleted_at, user)} end)
      |> Enum.split_with(&match?({_id, :ok}, &1))

    if deleted != [] do
      count = length(deleted)
      send(self(), {:toast, ngettext("1 entry deleted permanently", "%{count} entries deleted permanently", count)})
      update_list_entries(schema)
    end

    for {reason, rows} <- Enum.group_by(refused, &elem(elem(&1, 1), 1), &elem(&1, 0)) do
      message =
        gettext("Not deleted: %{entries}.", entries: refused_entries(rows, names)) <>
          " " <> purge_error_message(reason, length(rows))

      delete_refused(message)
    end

    {:halt, socket}
  end

  defp handle_listing_event(
         "duplicate_selected_to_language",
         %{"ids" => ids, "language" => language},
         %{assigns: %{current_user: user, schema: schema}} = socket,
         _listing_schema
       ) do
    ids = Jason.decode!(ids)
    singular = schema.__naming__().singular
    override_opts = [change_fields: language_copy_fields(schema, language), delete_fields: []]

    %{failed: failed, dropped_links: dropped} =
      Brando.Translations.copy_batch_to_language(schema, ids, language, user, override_opts)

    Enum.each(failed, fn {_id, error} -> log_duplicate_error(singular, error) end)

    if failed != [], do: send(self(), {:toast, gettext("Some entries could not be copied.")})

    if dropped > 0 do
      message =
        ngettext(
          "1 link to an entry with no version in this language was left out of the copies.",
          "%{count} links to entries with no version in this language were left out of the copies.",
          dropped
        )

      send(self(), {:toast, message})
    end

    update_list_entries(schema)

    {:halt, socket}
  end

  defp handle_listing_event(
         "duplicate_entry",
         %{"id" => entry_id},
         %{assigns: %{current_user: user}} = socket,
         schema
       ) do
    singular = schema.__naming__().singular
    context = schema.__modules__().context

    case apply(context, :"duplicate_#{singular}", [entry_id, user]) do
      {:ok, _} ->
        send(self(), {:toast, "#{String.capitalize(singular)} duplicated"})
        update_list_entries(schema)

      {:error, changeset} ->
        log_duplicate_error(singular, changeset)
        send(self(), {:toast, "Error duplicating #{String.capitalize(singular)}"})
    end

    {:halt, socket}
  end

  defp handle_listing_event(
         "duplicate_entry_to_language",
         %{"id" => entry_id, "language" => language},
         %{assigns: %{current_user: user, schema: schema}} = socket,
         _listing_schema
       ) do
    singular = schema.__naming__().singular
    context = schema.__modules__().context

    override_opts =
      [change_fields: language_copy_fields(schema, language)] ++ Brando.Translations.language_copy_opts(language)

    with :ok <- ensure_no_version_in(schema, entry_id, language),
         {:ok, duped_entry} <- apply(context, :"duplicate_#{singular}", [entry_id, user, override_opts]) do
      send(self(), {:toast, "#{String.capitalize(singular)} duplicated to [#{language}]"})

      # the entry is translatable, but might not have alternates setup
      if schema.has_alternates?() do
        # link the entries together
        _ = Module.concat([schema, Alternate]).add(entry_id, duped_entry.id)
      end

      update_url = schema.__admin_route__(:update, [duped_entry.id])
      send(self(), {:set_content_language_and_navigate, language, update_url})

      {:halt, socket}
    else
      error ->
        log_duplicate_error(singular, error)
        send(self(), {:toast, copy_error_message(error)})
        {:halt, socket}
    end
  end

  # "Create translation", and "Create and translate", which opens the new
  # translation's form with Translate with AI started there
  # (`?translate=ai`, `BrandoAdmin.LiveView.Form.Hooks`): the editor checks
  # and saves the texts, nothing is saved here. For a language whose version
  # is in the trash the row asks first, and the confirmed event carries
  # `replace`: that version is deleted for good and the new one created.
  defp handle_listing_event(
         event,
         %{"id" => source_id, "language" => language} = params,
         %{assigns: %{current_user: user, schema: schema}} = socket,
         _listing_schema
       )
       when event in ["create_entry_translation", "create_entry_translation_with_ai"] do
    create =
      if params["replace"] in [true, "true"],
        do: &Brando.Translations.replace_trashed_target/4,
        else: &Brando.Translations.create_target/4

    with :ok <- Brando.Authorization.Boundary.authorize(user, :create, schema),
         {:ok, target} <- create.(schema, source_id, language, user) do
      update_list_entries(schema)
      update_url = schema.__admin_route__(:update, [target.id])
      update_url = if event == "create_entry_translation_with_ai", do: update_url <> "?translate=ai", else: update_url
      send(self(), {:set_content_language_and_navigate, language, update_url})
    else
      # Refusals the editor is told about, as a delete's are
      {:error, reason} = error when reason in [:language_in_trash, :language_exists] ->
        send(self(), {:toast, translation_error_message(error)})

      error ->
        Logger.error("(!) Error creating a translation: #{inspect(error)}")
        send(self(), {:toast, translation_error_message(error)})
    end

    {:halt, socket}
  end

  defp handle_listing_event(
         "translate_entry_to_language",
         %{"id" => entry_id, "language" => language},
         %{assigns: %{current_user: user, schema: schema}} = socket,
         _listing_schema
       ) do
    singular = schema.__naming__().singular
    context = schema.__modules__().context
    list_id = "content_listing_#{schema}_default"

    # Open the dialog immediately
    send_update(BrandoAdmin.Components.Content.List,
      id: list_id,
      action: :translation_progress,
      translation_dialog: %{step: :duplicating, entry_url: nil}
    )

    override_opts =
      [change_fields: language_copy_fields(schema, language, Brando.Translations.slug_changes(schema, language))] ++
        Brando.Translations.language_copy_opts(language)

    with :ok <- ensure_no_version_in(schema, entry_id, language),
         {:ok, duped_entry} <- apply(context, :"duplicate_#{singular}", [entry_id, user, override_opts]) do
      start_entry_translation(schema, entry_id, duped_entry, language, user)
      {:halt, socket}
    else
      error ->
        log_duplicate_error(singular, error)

        send_update(BrandoAdmin.Components.Content.List,
          id: list_id,
          action: :translation_progress,
          translation_dialog: %{step: {:error, copy_error_message(error)}, entry_url: nil}
        )

        {:halt, socket}
    end
  end

  defp handle_listing_event("rerender_entry", %{"id" => entry_id}, socket, schema) do
    case Brando.Content.Blocks.render_entry(schema, entry_id) do
      {:ok, _entry} ->
        send(self(), {:toast, gettext("Entry re-rendered")})

      {:error, _} ->
        send(self(), {:toast, gettext("Error re-rendering entry")})
    end

    {:halt, socket}
  end

  defp handle_listing_event(_event, _params, socket, _schema), do: {:cont, socket}

  defp translated_singular(schema) do
    singular = schema.__naming__().singular
    domain = schema.__naming__().domain
    msgid = Utils.humanize(singular, :downcase)

    gettext_module = schema.__modules__(:gettext)
    gettext_domain = String.downcase("#{domain}_#{singular}")

    Gettext.dgettext(gettext_module, gettext_domain, msgid)
  end

  defp log_duplicate_error(singular, {:error, %Ecto.Changeset{} = changeset}),
    do: log_duplicate_error(singular, changeset)

  defp log_duplicate_error(singular, %Ecto.Changeset{} = changeset) do
    Logger.error("""
    (!) Error duplicating #{String.capitalize(singular)}

    Errors:
    #{inspect(changeset.errors, pretty: true)}

    Changes with errors:
    #{inspect(Map.take(changeset.changes, Keyword.keys(changeset.errors)), pretty: true)}
    """)
  end

  defp log_duplicate_error(singular, error) do
    Logger.error("(!) Error duplicating #{String.capitalize(singular)}: #{inspect(error, pretty: true)}")
  end

  defp delete_source(schema, entry_id, "delete", params, user) do
    Brando.Translations.delete_with_translations(schema, entry_id, params["translations_group"], user,
      source_args: delete_opts(schema, params),
      translation_args: translation_delete_opts(schema, params)
    )
  end

  defp delete_source(schema, entry_id, choice, params, user) when choice in ["transfer", "detach"] do
    successor = if choice == "transfer", do: params["translations_source"] || ""

    Brando.Translations.delete_keeping_translations(schema, entry_id, successor, params["translations_group"], user,
      source_args: delete_opts(schema, params)
    )
  end

  defp delete_source(_schema, _entry_id, _choice, _params, _user), do: {:error, :invalid_choice}

  # A delete from the listing that was refused or failed: the error toast,
  # which stays until closed
  defp delete_refused(message), do: send(self(), {:toast, message, :error})

  defp delete_error_message(schema, entry_id, :group_has_synchronized_members),
    do: synchronized_members_message(schema, entry_id)

  defp delete_error_message(_schema, entry_id, {:fragments, :group_has_synchronized_members}),
    do: BrandoAdmin.LiveView.Listing.DeleteDescription.synchronized_fragments_message(entry_id)

  defp delete_error_message(schema, _entry_id, {:translation, entry, reason}),
    do: BrandoAdmin.LiveView.Listing.DeleteDescription.translation_refused(schema, entry, translation_reason(reason))

  defp delete_error_message(_schema, _entry_id, :not_a_synchronized_target),
    do: gettext("Nothing was deleted: the new source must be one of its translations, outside the trash.")

  defp delete_error_message(_schema, _entry_id, :module_in_use), do: module_in_use_message()

  defp delete_error_message(_schema, _entry_id, {:fragments, :target_not_found}),
    do: gettext("The page chosen for the fragments is gone or in the trash. Nothing was deleted.")

  defp delete_error_message(_schema, _entry_id, :forbidden), do: gettext("You do not have permission to do this.")

  defp delete_error_message(schema, _entry_id, _reason),
    do: "#{gettext("Error deleting")} #{String.capitalize(translated_singular(schema))}"

  # Why `count` entries were not deleted permanently
  defp purge_error_message(:not_in_trash, count),
    do:
      ngettext(
        "It is no longer in the trash as it was shown: restored, deleted, or moved there again since.",
        "They are no longer in the trash as they were shown: restored, deleted, or moved there again since.",
        count
      )

  defp purge_error_message(:forbidden, count),
    do: ngettext("You may not delete it permanently.", "You may not delete them permanently.", count)

  defp purge_error_message({:referenced, constraint}, count) do
    case referring_schema(constraint) do
      nil ->
        ngettext("Other content still refers to it.", "Other content still refers to them.", count)

      schema ->
        kind = schema |> Brando.Blueprint.get_plural() |> String.downcase()
        ngettext("Some %{kind} still refer to it.", "Some %{kind} still refer to them.", count, kind: kind)
    end
  end

  defp purge_error_message({:retry, _reason}, _count),
    do: gettext("The video provider could not be reached. Try again later.")

  defp purge_error_message(:busy, _count),
    do: gettext("The video is being changed at its provider. Try again in a moment.")

  defp purge_error_message(:holdings_unavailable, _count),
    do: gettext("Could not check whether another site uses the video. Try again later.")

  defp purge_error_message(_reason, count),
    do: ngettext("It could not be deleted.", "They could not be deleted.", count)

  # The Blueprint whose table a foreign key `constraint` is on, by Ecto's
  # name for it, `<table>_<column>_fkey`: the longest table name it starts with
  defp referring_schema(constraint) when is_binary(constraint) do
    (Brando.Blueprint.list_blueprints() ++ Brando.Blueprint.brando_blueprints())
    |> Enum.uniq()
    |> Enum.filter(fn schema ->
      source = schema.__schema__(:source)
      is_binary(source) and String.starts_with?(constraint, source <> "_")
    end)
    |> Enum.max_by(&String.length(&1.__schema__(:source)), fn -> nil end)
  end

  defp referring_schema(_constraint), do: nil

  # The trash's deleted_at as the menu showed it, of the schema's type
  defp purge_entry(schema, entry_id, deleted_at, user) do
    deleted_at =
      with type when not is_nil(type) <- schema.__schema__(:type, :deleted_at),
           {:ok, deleted_at} <- Ecto.Type.cast(type, deleted_at) do
        deleted_at
      else
        _ -> nil
      end

    Brando.SoftDelete.Query.purge_entry(schema, entry_id, deleted_at, user)
  end

  # The refused rows by name, as far as the person may read them; the rest
  # are counted
  defp refused_entries(ids, names) do
    named = for id <- ids, name = names[id], do: "“#{name}”"

    case length(ids) - length(named) do
      0 -> Enum.join(named, ", ")
      hidden when named == [] -> pngettext("delete", "1 entry", "%{count} entries", hidden)
      hidden -> Enum.join(named ++ [pngettext("delete", "1 other entry", "%{count} other entries", hidden)], ", ")
    end
  end

  # The names of the entries among `ids` the person may read, in the read
  # scope the listing reads them in
  defp entry_names(schema, ids) do
    import Ecto.Query, only: [from: 2]

    readable = from(t in schema, where: t.id in ^ids) |> Brando.Authorization.Boundary.query(schema) |> Brando.Repo.all()

    for entry <- readable,
        into: %{},
        do: {entry.id, BrandoAdmin.LiveView.Listing.DeleteDescription.entry_name(schema, entry) || "##{entry.id}"}
  end

  defp translation_reason(:forbidden), do: gettext("You do not have permission to do this.")
  defp translation_reason({:taken, _constraint}), do: gettext("Another entry has its address now.")
  defp translation_reason(_reason), do: gettext("It could not be changed.")

  defp module_in_use_message,
    do: gettext("A module that blocks use was not deleted. Delete on its row lists the entries using it.")

  # A selection, or a delete without the dialog's choice
  defp synchronized_members_message(_schema, _entry_id),
    do:
      gettext(
        "Not deleted: this entry is the source of synchronized translations. Delete it from its own row to choose what becomes of them."
      )

  defp translation_error_message({:error, :language_in_trash}),
    do: gettext("This language's version is in the trash. Restore it from the trash instead.")

  defp translation_error_message({:error, :language_exists}), do: gettext("This language already has a version.")
  defp translation_error_message(_error), do: gettext("Could not create the translation")

  defp copy_error_message({:error, :language_exists}), do: gettext("This language already has a version.")
  defp copy_error_message({:error, :forbidden}), do: gettext("You do not have permission to do this.")
  defp copy_error_message(_error), do: gettext("Could not copy this entry. Nothing was saved.")

  # A language the entry is already linked to has its version: a copy would
  # give the entry two. The row menu leaves those languages out; this covers a
  # listing that hasn't caught up.
  defp ensure_no_version_in(schema, entry_id, language) do
    if language in Brando.Translations.alternate_languages(schema, entry_id),
      do: {:error, :language_exists},
      else: :ok
  end

  # The copy's language and the caller's `changes`, then a free value in that
  # language for each unique field: a page's URI that the language already
  # uses gets a number instead of failing the insert.
  defp language_copy_fields(schema, language, changes \\ []) do
    [{:language, String.to_existing_atom(language)} | changes] ++ Brando.Translations.free_unique_values(schema)
  end

  defp start_entry_translation(schema, entry_id, duped_entry, language, user) do
    singular = schema.__naming__().singular
    context = schema.__modules__().context

    if schema.has_alternates?() do
      _ = Module.concat([schema, Alternate]).add(entry_id, duped_entry.id)
    end

    entry_url = schema.__admin_route__(:update, [duped_entry.id])

    # Get source language from original entry
    {:ok, original} = apply(context, :"get_#{singular}", [entry_id])

    translation = %{
      lv_pid: self(),
      schema: schema,
      entry_id: duped_entry.id,
      source_lang: to_string(original.language),
      language: language,
      entry_url: entry_url,
      user: user
    }

    Task.start(Brando.Tenant.capture_context(fn -> run_entry_translation(translation) end))
  end

  defp run_entry_translation(%{lv_pid: lv_pid, schema: schema, entry_url: entry_url} = translation) do
    progress_fn = fn step ->
      send(lv_pid, {:translation_progress, schema, %{step: step, entry_url: entry_url}})
    end

    case Brando.AI.Translation.translate_entry(
           schema,
           translation.entry_id,
           translation.source_lang,
           translation.language,
           progress_fn
         ) do
      {:ok, _} ->
        send(
          lv_pid,
          {:translation_progress, schema, %{step: :complete, entry_url: entry_url, language: translation.language}}
        )

        update_list_entries(schema)

      {:error, reason} ->
        # Roll back: delete the duplicated entry
        singular = schema.__naming__().singular
        context = schema.__modules__().context
        apply(context, :"delete_#{singular}", [translation.entry_id, translation.user])
        update_list_entries(schema)

        send(
          lv_pid,
          {:translation_progress, schema, %{step: {:error, inspect(reason)}, entry_url: nil}}
        )
    end
  end

  defp attach_listing_info_hooks(socket, nil) do
    attach_hook(socket, :b_listing_infos, :handle_info, fn
      {:modal, type, title, message}, socket ->
        {:halt, push_event(socket, "b:alert", %{title: title, message: message, type: type})}

      {:toast, message}, %{assigns: %{current_user: current_user}} = socket ->
        BrandoAdmin.Toast.send_to(current_user, message)
        {:halt, socket}

      {:set_content_language_and_navigate, language, url}, %{assigns: %{current_user: current_user}} = socket ->
        {:ok, updated_current_user} =
          Brando.Users.update_user(
            current_user,
            %{config: %{content_language: language}},
            :system,
            show_notification: false
          )

        {:halt,
         socket
         |> assign(:current_user, updated_current_user)
         |> push_navigate(to: url)}

      _, socket ->
        {:cont, socket}
    end)
  end

  defp attach_listing_info_hooks(socket, _) do
    attach_hook(socket, :b_listing_infos, :handle_info, fn
      # The person's default view, which the list already shows: its URL
      # takes the place of the bare one (`Content.List`)
      {:open_listing_view, url}, socket ->
        {:halt, push_patch(socket, to: url, replace: true)}

      {schema, [:entries, :updated], []}, socket ->
        send_update(BrandoAdmin.Components.Content.List,
          id: "content_listing_#{schema}_default",
          action: :update_entries
        )

        {:halt, entries_updated(socket)}

      {:translation_progress, schema, dialog_state}, socket ->
        send_update(BrandoAdmin.Components.Content.List,
          id: "content_listing_#{schema}_default",
          action: :translation_progress,
          translation_dialog: dialog_state
        )

        {:halt, socket}

      {:modal, type, title, message}, socket ->
        {:halt, push_event(socket, "b:alert", %{title: title, message: message, type: type})}

      {:alert, message}, %{assigns: %{current_user: current_user}} = socket ->
        BrandoAdmin.Alert.send_to(current_user, message)
        {:halt, socket}

      {:toast, message}, %{assigns: %{current_user: current_user}} = socket ->
        BrandoAdmin.Toast.send_to(current_user, message)
        {:halt, socket}

      {:toast, message, level}, %{assigns: %{current_user: current_user}} = socket ->
        BrandoAdmin.Toast.send_to(current_user, message, %{level: level, type: :notification})
        {:halt, socket}

      {:set_content_language_and_navigate, language, url}, %{assigns: %{current_user: current_user}} = socket ->
        {:ok, updated_current_user} =
          Brando.Users.update_user(
            current_user,
            %{config: %{content_language: language}},
            :system,
            show_notification: false
          )

        {:halt,
         socket
         |> assign(:current_user, updated_current_user)
         |> push_navigate(to: url)}

      _, socket ->
        {:cont, socket}
    end)
  end

  def update_list_entries(schema) do
    topic = Brando.Tenant.Topic.scoped("brando:listing:content_listing_#{schema}_default")
    Phoenix.PubSub.broadcast(Brando.pubsub(), topic, {schema, [:entries, :updated], []})
  end

  defp subscribe(nil), do: :ok

  defp subscribe(schema) do
    topic = Brando.Tenant.Topic.scoped("brando:listing:content_listing_#{schema}_default")
    Phoenix.PubSub.subscribe(Brando.pubsub(), topic)
  end

  defp set_admin_locale(%{assigns: %{current_user: current_user}} = socket) do
    current_user.language
    |> to_string()
    |> Gettext.put_locale()

    socket
  end

  defp assign_schema(socket, schema) do
    assign_new(socket, :schema, fn -> schema end)
  end

  defp assign_title(%{assigns: %{schema: nil}} = socket) do
    assign(socket, :page_title, nil)
  end

  defp assign_title(%{assigns: %{schema: schema}} = socket) do
    translated_plural = Brando.Blueprint.get_plural(schema)
    page_title = String.capitalize(translated_plural)
    assign(socket, :page_title, page_title)
  end

  # The blueprint's icon, for the listing header (`icon={@page_icon}`).
  defp assign_page_icon(%{assigns: %{schema: nil}} = socket), do: assign(socket, :page_icon, nil)

  defp assign_page_icon(%{assigns: %{schema: schema}} = socket),
    do: assign(socket, :page_icon, Brando.Blueprint.get_icon(schema))

  defp assign_create_url(socket, schema) do
    assign_new(socket, :admin_create_url, fn ->
      try do
        if BrandoAdmin.Authorization.allowed?(:create, schema), do: schema.__admin_route__(:create, [])
      rescue
        UndefinedFunctionError -> nil
        FunctionClauseError -> nil
      end
    end)
  end

  # A listing view that shows more than its list refreshes it in
  # `entries_updated/1` (the pages listing's fragments without a page)
  defp entries_updated(%{view: view} = socket) do
    if function_exported?(view, :entries_updated, 1), do: view.entries_updated(socket), else: socket
  end

  # A page's fragments go where the editor chose in the delete dialog
  # (`DeleteDescription`); without a choice, `Brando.Pages.delete_page/3`'s default
  defp delete_opts(Brando.Pages.Page, %{"fragments" => "delete"}), do: [[fragments: :delete]]

  defp delete_opts(Brando.Pages.Page, %{"fragments" => "move"} = params) do
    case Map.get(params, "fragments_page") do
      page_id when page_id in [nil, ""] -> [[fragments: {:move, nil}]]
      page_id -> [[fragments: {:move, page_id}]]
    end
  end

  defp delete_opts(_schema, _params), do: []

  # The translations of a page deleted with it: their fragments go to the
  # trash too when the source's do, and otherwise where
  # `Brando.Pages.delete_page/3` moves them by default, in their own language
  defp translation_delete_opts(Brando.Pages.Page, %{"fragments" => "delete"}), do: [[fragments: :delete]]
  defp translation_delete_opts(_schema, _params), do: []
end
