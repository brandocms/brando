defmodule BrandoAdmin.LiveView.Listing.Hooks do
  @moduledoc """
  Runtime hooks for the public `BrandoAdmin.LiveView.Listing` entry point.
  """
  use Gettext, backend: Brando.Gettext

  import Phoenix.Component
  import Phoenix.LiveView

  alias Brando.Utils

  def hooks(_params, _, socket, schema) do
    if Phoenix.LiveView.connected?(socket) do
      subscribe(schema)
    end

    socket =
      socket
      |> assign(:socket_connected, true)
      |> set_admin_locale()
      |> assign_schema(schema)
      |> assign_create_url(schema)
      |> assign_title()
      |> attach_hooks(schema)

    {:cont, socket}
  end

  defp attach_hooks(socket, nil) do
    attach_listing_info_hooks(socket, nil)
  end

  defp attach_hooks(socket, schema) do
    socket
    |> attach_hook(:b_listing_events, :handle_event, fn
      "set_status", %{"id" => id, "status" => status, "schema" => target_schema}, socket ->
        target_schema = Module.concat([target_schema])
        Brando.Trait.Status.update_status(target_schema, id, status)
        update_list_entries(schema)

        {:halt, socket}

      "edit_entry", %{"id" => id}, socket ->
        update_url = schema.__admin_route__(:update, [id])
        {:halt, push_navigate(socket, to: update_url)}

      "undelete_entry", %{"id" => entry_id}, socket ->
        singular = schema.__naming__().singular
        domain = schema.__naming__().domain
        context = schema.__modules__().context
        msgid = Utils.humanize(singular, :downcase)

        gettext_module = schema.__modules__(:gettext)
        gettext_domain = String.downcase("#{domain}_#{singular}")

        translated_singular = Gettext.dgettext(gettext_module, gettext_domain, msgid)

        case apply(context, :"get_#{singular}", [entry_id]) do
          {:ok, entry} ->
            Brando.Repo.restore(entry)

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

      "delete_entry", %{"id" => entry_id}, %{assigns: %{current_user: user}} = socket ->
        if {:before_delete, 3} in schema.__info__(:functions) do
          schema.before_delete(entry_id, socket, self())
        end

        singular = schema.__naming__().singular
        domain = schema.__naming__().domain
        context = schema.__modules__().context
        msgid = Utils.humanize(singular, :downcase)

        gettext_module = schema.__modules__(:gettext)
        gettext_domain = String.downcase("#{domain}_#{singular}")

        translated_singular = Gettext.dgettext(gettext_module, gettext_domain, msgid)

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

      "delete_selected", %{"ids" => ids}, %{assigns: %{current_user: user, schema: schema}} = socket ->
        ids = Jason.decode!(ids)

        singular = schema.__naming__().singular
        context = schema.__modules__().context

        for entry_id <- ids do
          apply(context, :"delete_#{singular}", [entry_id, user])
        end

        update_list_entries(schema)

        {:halt, socket}

      "duplicate_selected_to_language",
      %{"ids" => ids, "language" => language},
      %{assigns: %{current_user: user, schema: schema}} = socket ->
        ids = Jason.decode!(ids)

        singular = schema.__naming__().singular
        context = schema.__modules__().context

        for entry_id <- ids do
          override_opts = [
            change_fields: [{:language, language}],
            delete_fields: []
          ]

          apply(context, :"duplicate_#{singular}", [entry_id, user, override_opts])
        end

        update_list_entries(schema)

        {:halt, socket}

      "duplicate_entry", %{"id" => entry_id}, %{assigns: %{current_user: user}} = socket ->
        singular = schema.__naming__().singular
        context = schema.__modules__().context

        case apply(context, :"duplicate_#{singular}", [entry_id, user]) do
          {:ok, _} ->
            send(self(), {:toast, "#{String.capitalize(singular)} duplicated"})
            update_list_entries(schema)

          {:error, changeset} ->
            require Logger

            Logger.error("""
            (!) Error duplicating #{String.capitalize(singular)}

            Errors:
            #{inspect(changeset.errors, pretty: true)}

            Changes with errors:
            #{inspect(Map.take(changeset.changes, Keyword.keys(changeset.errors)), pretty: true)}
            """)

            send(self(), {:toast, "Error duplicating #{String.capitalize(singular)}"})
        end

        {:halt, socket}

      "duplicate_entry_to_language",
      %{"id" => entry_id, "language" => language},
      %{assigns: %{current_user: user, schema: schema}} = socket ->
        singular = schema.__naming__().singular
        context = schema.__modules__().context

        override_opts = [
          change_fields: [{:language, String.to_existing_atom(language)}]
        ]

        case apply(context, :"duplicate_#{singular}", [entry_id, user, override_opts]) do
          {:ok, duped_entry} ->
            send(self(), {:toast, "#{String.capitalize(singular)} duplicated to [#{language}]"})

            # the entry is translatable, but might not have alternates setup
            if schema.has_alternates?() do
              # link the entries together
              _ = Module.concat([schema, Alternate]).add(entry_id, duped_entry.id)
            end

            update_url = schema.__admin_route__(:update, [duped_entry.id])
            send(self(), {:set_content_language_and_navigate, language, update_url})

            {:halt, socket}

          {:error, changeset} ->
            require Logger

            Logger.error("""
            (!) Error duplicating #{String.capitalize(singular)}

            Errors:
            #{inspect(changeset.errors, pretty: true)}

            Changes with errors:
            #{inspect(Map.take(changeset.changes, Keyword.keys(changeset.errors)), pretty: true)}
            """)

            send(self(), {:toast, "Error duplicating #{String.capitalize(singular)}"})
            {:halt, socket}
        end

      "translate_entry_to_language",
      %{"id" => entry_id, "language" => language},
      %{assigns: %{current_user: user, schema: schema}} = socket ->
        singular = schema.__naming__().singular
        context = schema.__modules__().context
        list_id = "content_listing_#{schema}_default"

        # Open the dialog immediately
        send_update(BrandoAdmin.Components.Content.List,
          id: list_id,
          action: :translation_progress,
          translation_dialog: %{step: :duplicating, entry_url: nil}
        )

        # Duplicate entry — change language and suffix slug fields to avoid unique constraint
        slug_change_fields =
          schema.__slug_fields__()
          |> Enum.map(fn slug_field ->
            {slug_field.name,
             fn _entry, current_value ->
               Utils.slugify("#{current_value}-#{language}")
             end}
          end)

        override_opts = [
          change_fields: [{:language, String.to_existing_atom(language)} | slug_change_fields]
        ]

        case apply(context, :"duplicate_#{singular}", [entry_id, user, override_opts]) do
          {:ok, duped_entry} ->
            if schema.has_alternates?() do
              _ = Module.concat([schema, Alternate]).add(entry_id, duped_entry.id)
            end

            entry_url = schema.__admin_route__(:update, [duped_entry.id])

            # Get source language from original entry
            {:ok, original} = apply(context, :"get_#{singular}", [entry_id])
            source_lang = to_string(original.language)

            # Spawn translation Task
            lv_pid = self()

            Task.start(fn ->
              progress_fn = fn step ->
                send(lv_pid, {:translation_progress, schema, %{step: step, entry_url: entry_url}})
              end

              case Brando.AI.Translation.translate_entry(
                     schema,
                     duped_entry.id,
                     source_lang,
                     language,
                     progress_fn
                   ) do
                {:ok, _} ->
                  send(
                    lv_pid,
                    {:translation_progress, schema, %{step: :complete, entry_url: entry_url, language: language}}
                  )

                  update_list_entries(schema)

                {:error, reason} ->
                  # Roll back: delete the duplicated entry
                  apply(context, :"delete_#{singular}", [duped_entry.id, user])
                  update_list_entries(schema)

                  send(
                    lv_pid,
                    {:translation_progress, schema, %{step: {:error, inspect(reason)}, entry_url: nil}}
                  )
              end
            end)

            {:halt, socket}

          {:error, _changeset} ->
            send_update(BrandoAdmin.Components.Content.List,
              id: list_id,
              action: :translation_progress,
              translation_dialog: %{step: {:error, "Duplication failed"}, entry_url: nil}
            )

            {:halt, socket}
        end

      "rerender_entry", %{"id" => entry_id}, socket ->
        case Brando.Content.Blocks.render_entry(schema, entry_id) do
          {:ok, _entry} ->
            send(self(), {:toast, gettext("Entry re-rendered")})

          {:error, _} ->
            send(self(), {:toast, gettext("Error re-rendering entry")})
        end

        {:halt, socket}

      _, _, socket ->
        {:cont, socket}
    end)
    |> attach_listing_info_hooks(schema)
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
    topic = "brando:listing:content_listing_#{schema}_default"
    Phoenix.PubSub.broadcast(Brando.pubsub(), topic, {schema, [:entries, :updated], []})
  end

  defp subscribe(nil), do: :ok

  defp subscribe(schema) do
    topic = "brando:listing:content_listing_#{schema}_default"
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

  defp assign_create_url(socket, schema) do
    assign_new(socket, :admin_create_url, fn ->
      try do
        schema.__admin_route__(:create, [])
      rescue
        UndefinedFunctionError -> nil
        FunctionClauseError -> nil
      end
    end)
  end
end
