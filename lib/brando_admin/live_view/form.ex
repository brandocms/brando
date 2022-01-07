defmodule BrandoAdmin.LiveView.Form do
  @moduledoc """
  A module that keeps using definitions for form live views

  This can be used in your application as:

      use BrandoAdmin.LiveView.Form, schema: MyApp.Projects.Project

  """
  import Phoenix.LiveView
  import Brando.Gettext
  alias Brando.Utils

  defmacro __using__(opts) do
    schema = Keyword.fetch!(opts, :schema)

    quote do
      use BrandoAdmin, :live_view

      on_mount({__MODULE__, :hooks})

      def on_mount(:hooks, params, assigns, socket) do
        BrandoAdmin.LiveView.Form.hooks(params, assigns, socket, unquote(schema))
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

  # with entry_id means it's an update
  def hooks(%{"entry_id" => entry_id}, %{"user_token" => token}, socket, schema) do
    if connected?(socket) do
      socket =
        socket
        |> assign(:socket_connected, true)
        |> assign_action(:update)
        |> assign_schema(schema)
        |> assign_title()
        |> assign_entry_id(entry_id)
        |> assign_current_user(token)
        |> set_admin_locale()
        |> attach_hooks(schema)

      {:cont, socket}
    else
      {:cont, assign(socket, :socket_connected, false)}
    end
  end

  def hooks(_params, %{"user_token" => token}, socket, schema) do
    if connected?(socket) do
      socket =
        socket
        |> assign(:socket_connected, true)
        |> assign_action(:create)
        |> assign_schema(schema)
        |> assign_title()
        |> assign_entry_id(nil)
        |> assign_current_user(token)
        |> set_admin_locale()
        |> attach_hooks(schema)

      {:cont, socket}
    else
      {:cont, assign(socket, :socket_connected, false)}
    end
  end

  defp assign_action(socket, action) do
    assign(socket, :form_action, action)
  end

  defp attach_hooks(socket, _schema) do
    socket
    |> attach_hook(:b_form_events, :handle_event, fn
      "update_focal_point",
      %{"field" => field, "x" => x, "y" => y},
      %{assigns: %{changeset: changeset}} = socket ->
        field_atom = String.to_existing_atom(field)
        updated_focal = %{x: x, y: y}

        updated_field =
          changeset
          |> Ecto.Changeset.get_field(field_atom)
          |> Map.from_struct()
          |> Map.put(:focal, updated_focal)

        updated_changeset = Ecto.Changeset.put_change(changeset, field_atom, updated_field)
        {:halt, assign(socket, changeset: updated_changeset)}

      _, _, socket ->
        {:cont, socket}
    end)
    |> attach_hook(:b_form_infos, :handle_info, fn
      {image, [:image, :updated], []}, socket ->
        case String.split(image.config_target, ":") do
          ["image", _schema, field_name] ->
            field_atom = String.to_existing_atom(field_name)
            schema = socket.assigns.schema
            singular = schema.__naming__().singular
            target_id = "#{singular}_form"

            send_update(BrandoAdmin.Components.Form,
              id: target_id,
              action: :update_entry_relation,
              updated_relation: image,
              field: field_atom,
              force_validation: true
            )

          _ ->
            nil
        end

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
    translated_singular =
      schema.__translations__()
      |> Utils.try_path([:naming, :singular])

    assign(
      socket,
      :page_title,
      (translated_singular && String.capitalize(translated_singular)) || nil
    )
  end

  defp assign_entry_id(socket, entry_id) do
    assign(socket, :entry_id, entry_id)
  end
end
