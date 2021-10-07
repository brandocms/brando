defmodule BrandoAdmin.LiveView.Listing do
  @moduledoc """
  A module that keeps using definitions for listing live views

  This can be used in your application as:

  use BrandoAdmin.LiveView.Listing, schema: MyApp.Projects.Project

  """
  import Phoenix.LiveView
  import Brando.Gettext
  alias Brando.Utils

  defmacro __using__(opts) do
    schema = Keyword.fetch!(opts, :schema)

    quote do
      use Surface.LiveView, layout: {BrandoAdmin.LayoutView, "live.html"}
      use Phoenix.HTML
      import Phoenix.LiveView.Helpers

      on_mount({__MODULE__, :hooks})

      def hooks(params, assigns, socket) do
        BrandoAdmin.LiveView.Listing.hooks(params, assigns, socket, unquote(schema))
      end

      # we need the uri on first load, so inject for now
      def handle_params(params, url, socket) do
        uri = URI.parse(url)

        {:noreply,
         socket
         |> assign(:params, params)
         |> assign(:uri, uri)}
      end
    end
  end

  def hooks(_params, %{"user_token" => token}, socket, schema) do
    if Phoenix.LiveView.connected?(socket) do
      subscribe(schema)
    end

    socket =
      socket
      |> assign(:socket_connected, true)
      |> assign_current_user(token)
      |> set_admin_locale()
      |> assign_schema(schema)
      |> assign_title()
      |> assign_blueprint(schema)
      |> attach_hooks(schema)

    {:cont, socket}
  end

  defp attach_hooks(socket, schema) do
    socket
    |> attach_hook(:b_listing_events, :handle_event, fn
      "edit_entry", %{"id" => id}, socket ->
        update_view = schema.__modules__().admin_update_view

        {:halt,
         push_redirect(socket, to: Brando.routes().admin_live_path(socket, update_view, id))}

      "delete_entry", %{"id" => entry_id}, %{assigns: %{current_user: user}} = socket ->
        singular = schema.__naming__().singular
        context = schema.__modules__().context

        case apply(context, :"delete_#{singular}", [entry_id, user]) do
          {:ok, _} ->
            send(self(), {:toast, "#{String.capitalize(singular)} deleted"})
            update_list_entries(schema)

          {:error, _error} ->
            send(self(), {:toast, "Error deleting #{String.capitalize(singular)}"})
        end

        {:halt, socket}

      "delete_selected", %{"ids" => ids}, socket ->
        ids = Jason.decode!(ids)
        require Logger
        Logger.error("==> delete selected #{inspect(ids)}")
        {:halt, socket}

      "duplicate_entry", %{"id" => entry_id}, %{assigns: %{current_user: user}} = socket ->
        singular = schema.__naming__().singular
        context = schema.__modules__().context

        case apply(context, :"duplicate_#{singular}", [entry_id, user]) do
          {:ok, _} ->
            send(self(), {:toast, "#{String.capitalize(singular)} duplicated"})
            update_list_entries(schema)

          {:error, _error} ->
            send(self(), {:toast, "Error duplicating #{String.capitalize(singular)}"})
        end

        {:halt, socket}

      _, _, socket ->
        {:cont, socket}
    end)
    |> attach_hook(:b_listing_infos, :handle_info, fn
      {schema, [:entries, :updated], []}, socket ->
        send_update(BrandoAdmin.Components.Content.List,
          id: "content_listing_#{schema}_default",
          action: :update_entries
        )

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

      _, socket ->
        {:cont, socket}
    end)
  end

  def update_list_entries(schema) do
    require Logger
    Logger.error("==> update_list_entries for #{inspect(schema)}")

    Phoenix.PubSub.broadcast(
      Brando.pubsub(),
      "brando:listing:content_listing_#{schema}_default",
      {schema, [:entries, :updated], []}
    )
  end

  defp subscribe(schema) do
    Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:listing:content_listing_#{schema}_default",
      link: true
    )
  end

  defp assign_current_user(socket, token) do
    assign_new(socket, :current_user, fn ->
      Brando.Users.get_user_by_session_token(token)
    end)
  end

  defp set_admin_locale(%{assigns: %{current_user: current_user}} = socket) do
    current_user.language
    |> to_string
    |> Gettext.put_locale()

    socket
  end

  defp assign_schema(socket, schema) do
    assign_new(socket, :schema, fn ->
      schema
    end)
  end

  defp assign_title(%{assigns: %{schema: schema}} = socket) do
    translated_plural =
      schema.__translations__()
      |> Utils.try_path([:naming, :plural])

    assign(
      socket,
      :page_title,
      (translated_plural && String.capitalize(translated_plural)) || nil
    )
  end

  defp assign_blueprint(socket, schema) do
    assign_new(socket, :blueprint, fn ->
      schema.__blueprint__()
    end)
  end
end
