defmodule BrandoAdmin do
  @moduledoc """
  A module that keeps using definitions for controllers,
  views and so on.

  This can be used in your application as:

      use BrandoAdmin, :controller
      use BrandoAdmin, :html

  Keep the definitions in this module short and clean,
  mostly focused on imports, uses and aliases.
  """

  def controller do
    quote do
      use Phoenix.Controller,
        namespace: BrandoAdmin,
        formats: [:html, :json],
        layouts: [html: BrandoAdmin.Layouts]

      import Brando.Utils, only: [current_user: 1, helpers: 1]
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView, layout: {BrandoAdmin.Layouts, :live}

      on_mount {BrandoAdmin.Hooks, :urls}

      # `Brando.RuntimeConfig.get/1`, not `Brando.config/1`: this runs during macro
      # expansion in every admin LiveView, so calling into `Brando` here gives each
      # of them a compile-time edge to it — and `Brando` sits inside Blueprint's
      # compile-connected component, so the edge closes a cycle that pulls the
      # whole admin into one recompilation unit. `RuntimeConfig` is the leaf that
      # exists for exactly this, and reads the same value. See issue #2737.
      if Application.compile_env(Brando.RuntimeConfig.get(:otp_app), :sql_sandbox) do
        on_mount {BrandoAdmin.Mounts.LiveAcceptance, {:default, __MODULE__}}
      end

      def handle_params(_, _, socket) do
        {:noreply, socket}
      end

      defoverridable handle_params: 3

      unquote(html_helpers())
    end
  end

  def child_live_view do
    quote do
      use Phoenix.LiveView, layout: {BrandoAdmin.Layouts, :live_child}

      if Application.compile_env(Brando.RuntimeConfig.get(:otp_app), :sql_sandbox) do
        on_mount {BrandoAdmin.Mounts.LiveAcceptance, {:default, __MODULE__}}
      end

      unquote(html_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(html_helpers())
    end
  end

  def component do
    quote do
      use Phoenix.Component
      import Brando.HTML

      import BrandoAdmin.Utils,
        only: [
          prepare_input_component: 1,
          send_to_ref: 2,
          toggle_dropdown: 1,
          toggle_dropdown: 2,
          show_dropdown: 1,
          show_dropdown: 2,
          hide_dropdown: 1,
          hide_dropdown: 2,
          toggle_drawer: 1,
          toggle_drawer: 2,
          show_modal: 1,
          show_modal: 2,
          hide_modal: 1,
          hide_modal: 2,
          make_id: 1,
          make_uid: 2
        ]
    end
  end

  def html do
    quote do
      use Phoenix.Component

      # Include general helpers for rendering HTML
      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      import Phoenix.HTML
      alias Phoenix.LiveView.JS

      # Import all HTML functions (forms, tags, etc)
      import Brando.HTML

      # Import LiveView and .heex helpers (live_render, live_patch, <.form>, etc)
      import Phoenix.Component
      import Plug.Conn, only: [get_session: 2]

      import BrandoAdmin.Utils,
        only: [
          prepare_subform_component: 1,
          prepare_input_component: 1,
          send_to_ref: 2,
          toggle_dropdown: 1,
          toggle_dropdown: 2,
          show_dropdown: 1,
          show_dropdown: 2,
          hide_dropdown: 1,
          hide_dropdown: 2,
          toggle_drawer: 1,
          toggle_drawer: 2,
          show_modal: 1,
          show_modal: 2,
          hide_modal: 1,
          hide_modal: 2,
          make_id: 1,
          make_uid: 2
        ]

      # Routes generation with the ~p sigil
      # unquote(verified_routes())
    end
  end

  def context do
    quote do
      import Brando.SoftDelete.Query
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
