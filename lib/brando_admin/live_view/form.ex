defmodule BrandoAdmin.LiveView.Form do
  @moduledoc """
  A module that keeps using definitions for form live views

  This can be used in your application as:

      use BrandoAdmin.LiveView.Form, schema: MyApp.Projects.Project

  """
  import Phoenix.LiveView
  import Phoenix.Component
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
    |> attach_hook(:b_form_params, :handle_params, &handle_params/3)
    |> attach_hook(:b_form_events, :handle_event, &handle_event/3)
    |> attach_hook(:b_form_infos, :handle_info, &handle_info/2)
  end

  defp handle_params(params, url, socket) do
    uri = URI.parse(url)

    {:halt,
     socket
     |> assign(:params, params)
     |> assign(:uri, uri)}
  end

  defp handle_event(
         "update_focal_point",
         %{"field" => field, "x" => x, "y" => y},
         %{assigns: %{changeset: changeset}} = socket
       ) do
    field_atom = String.to_existing_atom(field)
    updated_focal = %{x: x, y: y}

    updated_field =
      changeset
      |> Ecto.Changeset.get_field(field_atom)
      |> Map.from_struct()
      |> Map.put(:focal, updated_focal)

    require Logger
    Logger.error("== TODO: update_focal_point updating changeset here!")
    Logger.error(inspect(changeset, pretty: true))

    updated_changeset = Ecto.Changeset.put_change(changeset, field_atom, updated_field)
    {:halt, assign(socket, changeset: updated_changeset)}
  end

  defp handle_event(_, _, socket), do: {:cont, socket}

  defp handle_info({image, [:image, :updated], path}, socket) do
    case String.split(image.config_target, ":") do
      ["image", image_schema_binary, field_name] ->
        field_atom = String.to_existing_atom(field_name)
        schema = socket.assigns.schema
        image_schema = Module.concat([image_schema_binary])

        full_path =
          if image_schema != schema do
            path
          else
            [field_atom]
          end

        singular = schema.__naming__().singular
        target_id = "#{singular}_form"

        send_update(BrandoAdmin.Components.Form,
          id: target_id,
          action: :update_entry_relation,
          updated_relation: image,
          path: full_path,
          force_validation: true
        )

      ["gallery", _schema, field_name] ->
        schema = socket.assigns.schema
        singular = schema.__naming__().singular
        target_id = "#{singular}_form_form-#{field_name}"

        # update image in gallery input
        send_update(BrandoAdmin.Components.Form.Input.Gallery,
          id: target_id,
          action: :update_image,
          updated_image: image,
          force_validation: true
        )

      _ ->
        nil
    end

    {:halt, socket}
  end

  defp handle_info({_module, [:module, action]}, socket)
       when action in [:created, :updated] do
    schema = socket.assigns.schema
    singular = schema.__naming__().singular

    for %{name: field} <- schema.__villain_fields__() do
      target_id = "#{singular}_form_form-#{field}-blocks-module-picker"

      send_update(BrandoAdmin.Components.Form.Input.Blocks.ModulePicker,
        id: target_id,
        action: :refresh_modules
      )
    end

    {:halt, socket}
  end

  defp handle_info({:toast, message}, %{assigns: %{current_user: current_user}} = socket) do
    BrandoAdmin.Toast.send_to(current_user, message)
    {:halt, socket}
  end

  defp handle_info(
         {:set_content_language, language},
         %{assigns: %{current_user: current_user}} = socket
       ) do
    updated_data = %{config: %{content_language: language}}

    {:ok, updated_current_user} =
      Brando.Users.update_user(
        current_user,
        updated_data,
        :system,
        show_notification: false
      )

    toast_message =
      gettext("Content language is now %{language}", language: String.upcase(language))

    send(self(), {:toast, toast_message})
    # send a message that the language has switched. we use this
    # for special views like identity_live and seo_live
    send(self(), {:content_language, language})

    {:halt, assign(socket, :current_user, updated_current_user)}
  end

  defp handle_info(_, socket) do
    {:cont, socket}
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

  defp set_admin_locale(%{assigns: %{current_user: current_user}} = socket) do
    current_user.language
    |> to_string
    |> Gettext.put_locale()

    socket
  end
end
