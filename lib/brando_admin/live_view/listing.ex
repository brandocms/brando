defmodule BrandoAdmin.LiveView.Listing do
  @moduledoc """
  A module that keeps using definitions for listing live views

  This can be used in your application as:

  use BrandoAdmin.LiveView.Listing, schema: MyApp.Projects.Project

  """
  import Phoenix.LiveView
  import Phoenix.Component
  import Brando.Gettext
  alias Brando.Utils

  defmacro __using__(opts) do
    schema = Keyword.fetch!(opts, :schema)

    quote do
      use BrandoAdmin, :live_view
      # use Phoenix.HTML
      import Phoenix.Component

      on_mount({__MODULE__, :hooks})

      def on_mount(:hooks, params, assigns, socket) do
        BrandoAdmin.LiveView.Listing.hooks(params, assigns, socket, unquote(schema))
      end
    end
  end

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
        update_view = schema.__modules__().admin_update_view

        {:halt,
         push_redirect(socket, to: Brando.routes().admin_live_path(socket, update_view, id))}

      "undelete_entry", %{"id" => entry_id}, socket ->
        singular = schema.__naming__().singular
        domain = schema.__naming__().domain
        context = schema.__modules__().context
        msgid = Brando.Utils.humanize(singular, :downcase)

        gettext_module = schema.__modules__(:gettext)
        gettext_domain = String.downcase("#{domain}_#{singular}_naming")

        translated_singular = Gettext.dgettext(gettext_module, gettext_domain, msgid)

        case apply(context, :"get_#{singular}", [entry_id]) do
          {:ok, entry} ->
            Brando.repo().restore(entry)

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
        msgid = Brando.Utils.humanize(singular, :downcase)

        gettext_module = schema.__modules__(:gettext)
        gettext_domain = String.downcase("#{domain}_#{singular}_naming")

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

      "delete_selected",
      %{"ids" => ids},
      %{assigns: %{current_user: user, schema: schema}} = socket ->
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
        update_view = schema.__modules__().admin_update_view

        override_opts = [
          change_fields: [{:language, language}],
          delete_fields: []
        ]

        {:ok, duped_entry} =
          apply(context, :"duplicate_#{singular}", [entry_id, user, override_opts])

        send(self(), {:toast, "#{String.capitalize(singular)} duplicated to [#{language}]"})

        # the entry is translatable, but might not have alternates setup
        if schema.has_alternates?() do
          # link the entries together
          _ = Module.concat([schema, Alternate]).add(entry_id, duped_entry.id)
        end

        send(
          self(),
          {:set_content_language_and_navigate, language,
           Brando.routes().admin_live_path(socket, update_view, duped_entry.id)}
        )

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
          {:toast,
           gettext("Content language is now %{language}", language: String.upcase(language))}
        )

        {:halt, assign(socket, :current_user, updated_current_user)}

      {:set_content_language_and_navigate, language, url},
      %{assigns: %{current_user: current_user}} = socket ->
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
          {:toast,
           gettext("Content language is now %{language}", language: String.upcase(language))}
        )

        {:halt, assign(socket, :current_user, updated_current_user)}

      {:set_content_language_and_navigate, language, url},
      %{assigns: %{current_user: current_user}} = socket ->
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
    Phoenix.PubSub.subscribe(Brando.pubsub(), topic, link: true)
  end

  defp set_admin_locale(%{assigns: %{current_user: current_user}} = socket) do
    current_user.language
    |> to_string
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
    translated_plural = Utils.try_path(schema.__translations__(), [:naming, :plural])
    page_title = (translated_plural && String.capitalize(translated_plural)) || nil
    assign(socket, :page_title, page_title)
  end

  defp assign_create_url(socket, schema) do
    assign_new(socket, :admin_create_url, fn ->
      try do
        Brando.helpers().admin_live_path(
          Brando.endpoint(),
          schema.__modules__().admin_create_view
        )
      rescue
        _ -> nil
      end
    end)
  end
end
