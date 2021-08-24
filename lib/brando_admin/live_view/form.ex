defmodule BrandoAdmin.LiveView.Form do
  @moduledoc """
  A module that keeps using definitions for form live views

  This can be used in your application as:

      use BrandoAdmin.LiveView.Form, schema: MyApp.Projects.Project

  """
  import Phoenix.LiveView
  alias BrandoAdmin.Toast

  @callback query_params(id :: integer | binary) :: map

  defmacro __using__(opts) do
    schema = Keyword.fetch!(opts, :schema)

    quote do
      @behaviour BrandoAdmin.LiveView.Form
      use Surface.LiveView, layout: {BrandoAdmin.LayoutView, "live.html"}
      use BrandoAdmin.Toast
      use BrandoAdmin.Presence
      use Phoenix.HTML
      import Phoenix.LiveView.Helpers

      on_mount({__MODULE__, :hooks})

      def hooks(params, assigns, socket) do
        BrandoAdmin.LiveView.Form.hooks(params, assigns, socket, unquote(schema), __MODULE__)
      end

      # we need the uri on first load, so inject for now
      def handle_params(params, url, socket) do
        uri = URI.parse(url)

        {:noreply,
         socket
         |> assign(:params, params)
         |> assign(:uri, uri)}
      end

      def query_params(id), do: %{matches: %{id: id}}
      defoverridable query_params: 1
    end
  end

  # with entry_id means it's an update
  def hooks(%{"entry_id" => entry_id}, %{"user_token" => token}, socket, schema, caller) do
    socket =
      socket
      |> Surface.init()
      |> assign_action(:update)
      |> assign_schema(schema)
      |> assign_entry(schema, entry_id, caller)
      |> assign_current_user(token)
      |> set_admin_locale()
      |> attach_hooks(schema)

    {:cont, socket}
  end

  def hooks(_params, %{"user_token" => token}, socket, schema, _caller) do
    socket =
      socket
      |> Surface.init()
      |> assign_action(:create)
      |> assign_schema(schema)
      |> assign_current_user(token)
      |> set_admin_locale()
      |> attach_hooks(schema)

    {:cont, socket}
  end

  defp assign_action(socket, action) do
    assign(socket, :form_action, action)
  end

  defp attach_hooks(socket, schema) do
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

        updated_changeset = Ecto.Changeset.put_change(changeset, field, updated_field)
        {:halt, assign(socket, changeset: updated_changeset)}

      _, _, socket ->
        {:cont, socket}
    end)
    |> attach_hook(:b_form_infos, :handle_info, fn
      {:save, changeset}, %{assigns: %{current_user: user}} = socket ->
        list_view = schema.__modules__.admin_list_view
        singular = schema.__naming__.singular
        context = schema.__modules__.context

        mutation_type = (Ecto.Changeset.get_field(changeset, :id) && "update") || "create"

        case apply(context, :"#{mutation_type}_#{singular}", [changeset, user]) do
          {:ok, _} ->
            Toast.send_delayed("#{String.capitalize(singular)} #{mutation_type}d")
            {:halt, push_redirect(socket, to: Brando.routes().live_path(socket, list_view))}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:halt, assign(socket, changeset: changeset)}
        end

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

  defp assign_entry(socket, schema, entry_id, caller) do
    query_params = apply(caller, :query_params, [entry_id])
    singular = schema.__naming__.singular
    context = schema.__modules__.context
    assign_new(socket, :entry, fn -> apply(context, :"get_#{singular}!", [query_params]) end)
  end
end
