defmodule BrandoAdmin.LiveView.Listing.Hooks do
  @moduledoc """
  Runtime hooks for the public `BrandoAdmin.LiveView.Listing` entry point.
  """
  use Gettext, backend: Brando.Gettext

  import Phoenix.Component
  import Phoenix.LiveView

  alias Brando.Utils

  require Logger

  def hooks(_params, _, socket, schema) do
    if Phoenix.LiveView.connected?(socket) do
      subscribe(schema)
    end

    socket =
      socket
      |> assign(:socket_connected, true)
      # The layout marks its container so the listing stylesheet can key on a
      # class. It used to derive this with `:has(> .content-list-wrapper)` on
      # that container — which sits above the block editor, so every DOM
      # mutation in an entry form paid for re-evaluating it. A schema-less
      # listing is a dashboard, which renders no list and takes no treatment.
      |> assign(:admin_workspace?, not is_nil(schema))
      |> set_admin_locale()
      |> assign_schema(schema)
      |> assign_create_url(schema)
      |> assign_title()
      |> assign_page_icon()
      |> attach_hooks(schema)

    {:cont, socket}
  end

  defp attach_hooks(socket, nil) do
    attach_listing_info_hooks(socket, nil)
  end

  defp attach_hooks(socket, schema) do
    socket
    |> attach_hook(:b_listing_events, :handle_event, &handle_listing_event(&1, &2, &3, schema))
    |> attach_listing_info_hooks(schema)
  end

  defp handle_listing_event(
         "set_status",
         %{"id" => id, "status" => status, "schema" => target_schema},
         socket,
         schema
       ) do
    target_schema = Brando.Authorization.Catalog.schema(target_schema)
    Brando.Trait.Status.update_status(target_schema, id, status, socket.assigns.current_user)
    update_list_entries(schema)

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

    case apply(context, :"get_#{singular}", [entry_id]) do
      {:ok, entry} ->
        Brando.Authorization.Boundary.restore(socket.assigns.current_user, entry)

        send(
          self(),
          {:toast, "#{String.capitalize(translated_singular)} #{gettext("undeleted")}"}
        )

        update_list_entries(schema)

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

  defp handle_listing_event(
         "delete_entry",
         %{"id" => entry_id},
         %{assigns: %{current_user: user}} = socket,
         schema
       ) do
    if {:before_delete, 3} in schema.__info__(:functions) do
      schema.before_delete(entry_id, socket, self())
    end

    singular = schema.__naming__().singular
    context = schema.__modules__().context
    translated_singular = translated_singular(schema)

    case apply(context, :"delete_#{singular}", [entry_id, user]) do
      {:ok, _} ->
        send(
          self(),
          {:toast, "#{String.capitalize(translated_singular)} #{gettext("deleted")}"}
        )

        update_list_entries(schema)

      {:error, _error} ->
        send(
          self(),
          {:toast, "#{gettext("Error deleting")} #{String.capitalize(translated_singular)}"}
        )
    end

    {:halt, socket}
  end

  defp handle_listing_event(
         "delete_selected",
         %{"ids" => ids},
         %{assigns: %{current_user: user, schema: schema}} = socket,
         _listing_schema
       ) do
    ids = Jason.decode!(ids)

    singular = schema.__naming__().singular
    context = schema.__modules__().context

    for entry_id <- ids do
      apply(context, :"delete_#{singular}", [entry_id, user])
    end

    update_list_entries(schema)

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
    context = schema.__modules__().context

    override_opts = [
      change_fields: language_copy_fields(schema, language),
      delete_fields: []
    ]

    failed =
      Enum.count(ids, fn entry_id ->
        case apply(context, :"duplicate_#{singular}", [entry_id, user, override_opts]) do
          {:ok, _} ->
            false

          error ->
            log_duplicate_error(singular, error)
            true
        end
      end)

    if failed > 0, do: send(self(), {:toast, gettext("Some entries could not be copied.")})

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

    override_opts = [change_fields: language_copy_fields(schema, language)]

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

  defp handle_listing_event(
         "create_entry_translation",
         %{"id" => source_id, "language" => language},
         %{assigns: %{current_user: user, schema: schema}} = socket,
         _listing_schema
       ) do
    with :ok <- Brando.Authorization.Boundary.authorize(user, :create, schema),
         {:ok, target} <- Brando.Translations.create_target(schema, source_id, language, user) do
      update_list_entries(schema)
      update_url = schema.__admin_route__(:update, [target.id])
      send(self(), {:set_content_language_and_navigate, language, update_url})
    else
      error ->
        Logger.error("(!) Error creating a translation: #{inspect(error)}")
        send(self(), {:toast, gettext("Could not create the translation")})
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

    override_opts = [
      change_fields: language_copy_fields(schema, language, translation_slug_changes(schema, language))
    ]

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

  # Duplicate entry — change language and suffix slug fields to avoid unique constraint
  defp translation_slug_changes(schema, language) do
    Enum.map(schema.__slug_fields__(), fn slug_field ->
      {slug_field.name,
       fn _entry, current_value ->
         Utils.slugify("#{current_value}-#{language}")
       end}
    end)
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

      {:set_content_language, language}, %{assigns: %{current_user: current_user}} = socket ->
        {:ok, updated_current_user} =
          Brando.Users.update_user(
            current_user,
            %{config: %{content_language: language}},
            :system,
            show_notification: false
          )

        send(
          self(),
          {:toast, gettext("Content language is now %{language}", language: String.upcase(language))}
        )

        {:halt, assign(socket, :current_user, updated_current_user)}

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

        {:halt, socket}

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

      {:set_content_language, language}, %{assigns: %{current_user: current_user}} = socket ->
        {:ok, updated_current_user} =
          Brando.Users.update_user(
            current_user,
            %{config: %{content_language: language}},
            :system,
            show_notification: false
          )

        send(
          self(),
          {:toast, gettext("Content language is now %{language}", language: String.upcase(language))}
        )

        {:halt, assign(socket, :current_user, updated_current_user)}

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
end
