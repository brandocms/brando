defmodule BrandoAdmin.LiveView.Form do
  @moduledoc """
  A module that keeps using definitions for form live views

  This can be used in your application as:

      use BrandoAdmin.LiveView.Form, schema: MyApp.Projects.Project

  """
  import Phoenix.LiveView
  import Phoenix.Component
  use Gettext, backend: Brando.Gettext

  defmacro __using__(opts) do
    schema = Keyword.fetch!(opts, :schema)
    skip_image_hooks = Keyword.get(opts, :skip_image_hooks, false)

    quote do
      use BrandoAdmin, :live_view

      on_mount({BrandoAdmin.LiveView.Form, {:setup, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_toast, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_progress_popup, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_alert, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_content_language, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_dirty_fields, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_active_field, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_modules, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_focal_point, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_mutations, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_mutation_listener, unquote(schema)}})

      unless unquote(skip_image_hooks) do
        on_mount({BrandoAdmin.LiveView.Form, {:hooks_images, unquote(schema)}})
      end
    end
  end

  def on_mount({:setup, schema}, %{"entry_id" => entry_id}, _session, socket) do
    if connected?(socket) do
      socket =
        socket
        |> assign(:socket_connected, true)
        |> set_admin_locale()
        |> assign_action(:update)
        |> assign_schema(schema)
        |> assign_entry_id(entry_id)
        |> assign_title()
        |> assign(:mutation_listeners, %{})

      Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:dirty_fields:#{entry_id}")
      Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:active_field:#{entry_id}")

      {:cont, socket}
    else
      {:cont, assign(socket, :socket_connected, false)}
    end
  end

  def on_mount({:setup, schema}, _params, _session, socket) do
    if connected?(socket) do
      socket =
        socket
        |> assign(:socket_connected, true)
        |> set_admin_locale()
        |> assign_action(:create)
        |> assign_schema(schema)
        |> assign_entry_id(nil)
        |> assign_title()
        |> assign(:mutation_listeners, %{})

      {:cont, socket}
    else
      {:cont, assign(socket, :socket_connected, false)}
    end
  end

  def on_mount({:hooks_images, _schema}, _params, _session, socket) do
    {:cont, attach_hook(socket, :b_form_images, :handle_info, &handle_hooks_image_info/2)}
  end

  def on_mount({:hooks_toast, _schema}, _params, _session, socket) do
    {:cont, attach_hook(socket, :b_form_toast, :handle_info, &handle_hooks_toast_info/2)}
  end

  def on_mount({:hooks_progress_popup, _schema}, _params, _session, socket) do
    {:cont,
     attach_hook(
       socket,
       :b_form_progress_popup,
       :handle_info,
       &handle_hooks_progress_popup_info/2
     )}
  end

  def on_mount({:hooks_alert, _schema}, _params, _session, socket) do
    {:cont, attach_hook(socket, :b_form_alert, :handle_info, &handle_hooks_alert_info/2)}
  end

  def on_mount({:hooks_content_language, _schema}, _params, _session, socket) do
    {:cont,
     attach_hook(
       socket,
       :b_form_content_language,
       :handle_info,
       &handle_hooks_content_language_info/2
     )}
  end

  def on_mount({:hooks_dirty_fields, _schema}, _params, _session, socket) do
    {:cont,
     attach_hook(
       socket,
       :b_form_dirty_fields,
       :handle_info,
       &handle_hooks_dirty_fields_info/2
     )}
  end

  def on_mount({:hooks_active_field, _schema}, _params, _session, socket) do
    {:cont,
     attach_hook(
       socket,
       :b_form_active_field,
       :handle_info,
       &handle_hooks_active_field_info/2
     )}
  end

  def on_mount({:hooks_modules, _schema}, _params, _session, socket) do
    {:cont,
     attach_hook(
       socket,
       :b_form_modules,
       :handle_info,
       &handle_hooks_modules_info/2
     )}
  end

  def on_mount({:hooks_mutation_listener, _schema}, _params, _session, socket) do
    {:cont,
     attach_hook(
       socket,
       :b_form_mutation_listener,
       :handle_info,
       &handle_hooks_mutation_listener_info/2
     )}
  end

  def on_mount({:hooks_mutations, _schema}, _params, _session, socket) do
    {:cont,
     attach_hook(
       socket,
       :b_form_mutations,
       :handle_info,
       &handle_hooks_mutations_info/2
     )}
  end

  def on_mount({:hooks_focal_point, _schema}, _params, _session, socket) do
    {:cont,
     attach_hook(
       socket,
       :b_form_focal_point,
       :handle_event,
       &handle_hooks_focal_point_event/3
     )}
  end

  defp handle_hooks_focal_point_event(
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

    updated_changeset = Ecto.Changeset.put_change(changeset, field_atom, updated_field)
    {:halt, assign(socket, changeset: updated_changeset)}
  end

  defp handle_hooks_focal_point_event(_, _, socket), do: {:cont, socket}

  defp handle_hooks_image_info({image, [:image, :processing], path}, socket) do
    case String.split(image.config_target, ":") do
      ["image", image_schema_binary, field_name] ->
        field_atom = String.to_existing_atom(field_name)
        schema = socket.assigns.schema
        image_schema = Module.concat([image_schema_binary])

        full_path =
          if image_schema == schema do
            [field_atom]
          else
            path
          end

        singular = schema.__naming__().singular
        target_id = "#{singular}_form"

        image = Map.put(image, :status, :unprocessed)

        send_update(BrandoAdmin.Components.Form,
          id: target_id,
          action: :update_entry_relation,
          updated_relation: image,
          path: full_path,
          force_validation: true
        )

      _ ->
        nil
    end

    {:halt, socket}
  end

  defp handle_hooks_image_info({image, [:image, :updated], path}, socket) do
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
          action: :image_processed,
          image_id: image.id
        )

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
        target_id = "#{singular}_#{field_name}"

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

  defp handle_hooks_image_info(_, socket), do: {:cont, socket}

  defp handle_hooks_alert_info({:alert, message}, %{assigns: %{current_user: current_user}} = socket) do
    BrandoAdmin.Alert.send_to(current_user, message)
    {:halt, socket}
  end

  defp handle_hooks_alert_info(_, socket), do: {:cont, socket}

  defp handle_hooks_toast_info({:toast, message}, %{assigns: %{current_user: current_user}} = socket) do
    BrandoAdmin.Toast.send_to(current_user, message)
    {:halt, socket}
  end

  defp handle_hooks_toast_info(_, socket), do: {:cont, socket}

  defp handle_hooks_progress_popup_info({:progress_popup, message}, %{assigns: %{current_user: current_user}} = socket) do
    BrandoAdmin.ProgressPopup.send_to(current_user, message)
    {:halt, socket}
  end

  defp handle_hooks_progress_popup_info(_, socket), do: {:cont, socket}

  defp handle_hooks_content_language_info(
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

  defp handle_hooks_content_language_info(_, socket), do: {:cont, socket}

  defp handle_hooks_dirty_fields_info({:dirty_fields, fields, user_id}, socket) do
    socket =
      if user_id == socket.assigns.current_user.id do
        Brando.presence().update_dirty_fields(socket.assigns.uri.path, user_id, fields)
        socket
      else
        # TODO: there are updated dirty fields from other users.
        require Logger

        Logger.debug("""

        ==> dirty_fields

        #{inspect(fields, pretty: true)}
        #{inspect(user_id, pretty: true)}

        """)

        socket
      end

    {:halt, socket}
  end

  defp handle_hooks_dirty_fields_info(_, socket), do: {:cont, socket}

  defp handle_hooks_active_field_info({:active_field, field, user_id}, socket) do
    socket =
      if user_id == socket.assigns.current_user.id do
        Brando.presence().update_active_field(socket.assigns.uri.path, user_id, field)
        socket
      else
        push_event(socket, "b:set_active_field", %{user_id: user_id, field: field})
      end

    {:halt, socket}
  end

  defp handle_hooks_active_field_info(_, socket), do: {:cont, socket}

  defp handle_hooks_modules_info({_module, [:module, action]}, socket) when action in [:created, :updated] do
    schema = socket.assigns.schema

    for %{name: field} <- schema.__blocks_fields__() do
      target_id = "block-field-#{field}-module-picker"

      send_update(BrandoAdmin.Components.Form.BlockField.ModulePicker,
        id: target_id,
        event: :refresh_modules
      )
    end

    {:halt, socket}
  end

  defp handle_hooks_modules_info(_, socket), do: {:cont, socket}

  defp handle_hooks_mutation_listener_info({:register_mutation_listener, schema, target}, socket) do
    Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:mutations:#{inspect(schema)}")

    {:halt,
     update(socket, :mutation_listeners, fn mls ->
       Map.update(mls, schema, [target], &[target | &1])
     end)}
  end

  defp handle_hooks_mutation_listener_info(_, socket), do: {:cont, socket}

  defp handle_hooks_mutations_info({:mutation, module, _entry, _action}, socket) do
    targets = Map.get(socket.assigns.mutation_listeners, module, [])

    for target <- targets do
      send_update(
        target,
        action: :force_refresh_options
      )
    end

    {:halt, socket}
  end

  defp handle_hooks_mutations_info(_, socket), do: {:cont, socket}

  defp assign_schema(socket, schema) do
    assign_new(socket, :schema, fn ->
      schema
    end)
  end

  defp assign_title(%{assigns: %{schema: schema}} = socket) do
    translated_singular = Brando.Blueprint.get_singular(schema)
    entry_id = socket.assigns.entry_id || gettext("New")

    assign(
      socket,
      :page_title,
      "#{translated_singular} [\##{entry_id}]"
    )
  end

  defp assign_entry_id(socket, entry_id) do
    assign(socket, :entry_id, entry_id)
  end

  defp set_admin_locale(%{assigns: %{current_user: current_user}} = socket) do
    current_user.language
    |> to_string()
    |> Gettext.put_locale()

    socket
  end

  defp assign_action(socket, action) do
    assign(socket, :form_action, action)
  end
end
