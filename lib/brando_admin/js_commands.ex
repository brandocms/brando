defmodule BrandoAdmin.JSCommands do
  @moduledoc """
  The admin's shared `Phoenix.LiveView.JS` command builders — dropdowns, modals,
  drawers.

  A leaf on purpose: it depends on nothing but `Phoenix.LiveView.JS`. Blueprint's
  `listings` DSL evaluates a `selection_action`'s event at compile time, so a
  schema that declares one takes a compile-time dependency on wherever these
  live. When that was `BrandoAdmin.Utils` — which uses the translator and imports
  `Phoenix.Component` — a core content schema recompiled with the admin. See
  issue #2737.

  `BrandoAdmin.Utils` delegates to these, so admin code can keep calling them
  there.
  """
  alias Phoenix.LiveView.JS

  def toggle_dropdown(js \\ %JS{}, dropdown_id) do
    JS.toggle(js,
      to: dropdown_id,
      in: {"transition ease-out duration-300", "opacity-0 y-100", "opacity-100 y-0"},
      out: {"transition ease-in duration-300", "opacity-100 y-0", "opacity-0 y-100"},
      time: 300
    )
  end

  def show_dropdown(js \\ %JS{}, dropdown_id) do
    JS.show(js,
      to: dropdown_id,
      transition: {"transition ease-out duration-300", "opacity-0 y-100", "opacity-100 y-0"},
      time: 300
    )
  end

  def hide_dropdown(js \\ %JS{}, dropdown_id) do
    JS.hide(js,
      to: dropdown_id,
      transition: {"transition ease-in duration-300", "opacity-100 y-0", "opacity-0 y-100"},
      time: 300
    )
  end

  def show_modal(js \\ %JS{}, modal_id) do
    js
    |> JS.show(
      to: "#{modal_id}",
      display: "flex",
      blocking: false,
      time: 0
    )
    |> JS.show(
      to: "#{modal_id} .modal-backdrop",
      transition: {"transition ease-out duration-200", "opacity-0", "opacity-100"},
      blocking: false,
      time: 200
    )
    |> JS.show(
      to: "#{modal_id} .modal-dialog",
      blocking: false,
      transition: {"transition ease-out duration-200", "opacity-0 y-100", "opacity-100 y-0"},
      time: 200
    )
  end

  def hide_modal(js \\ %JS{}, modal_id) do
    js
    |> JS.hide(
      to: "#{modal_id} .modal-dialog",
      transition: {"transition ease-in duration-100", "opacity-100 y-0", "opacity-0 y-100"},
      blocking: true,
      time: 100
    )
    |> JS.hide(
      to: "#{modal_id} .modal-backdrop",
      transition: {"transition ease-in duration-100", "opacity-100", "opacity-0"},
      blocking: false,
      time: 100
    )
    |> JS.hide(
      to: "#{modal_id}",
      transition: {"transition", "opacity-100", "opacity-100"},
      blocking: false,
      time: 100
    )
  end

  def toggle_drawer(js \\ %JS{}, drawer_id) do
    JS.toggle(js,
      to: drawer_id,
      in: {"transition ease-out duration-300", "x-100", "x-0"},
      out: {"transition ease-in duration-300", "x-0", "x-100"},
      time: 300
    )
  end
end
