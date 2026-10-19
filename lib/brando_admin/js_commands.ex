defmodule BrandoAdmin.JSCommands do
  # The admin's shared `Phoenix.LiveView.JS` command builders — dropdowns,
  # modals, drawers.
  #
  # A leaf on purpose: it depends on nothing but `Phoenix.LiveView.JS`.
  # Blueprint's `listings` DSL evaluates a `selection_action`'s event at compile
  # time, so a schema that declares one takes a compile-time dependency on
  # wherever these live. If that were BrandoAdmin.Utils — which uses the
  # translator and imports `Phoenix.Component` — a core content schema would
  # recompile with the admin. See issue #2737.
  #
  # BrandoAdmin.Utils delegates to these, so admin code can keep calling them
  # there.
  @moduledoc false
  alias Phoenix.LiveView.JS

  def toggle_dropdown(js \\ %JS{}, dropdown_id) do
    JS.toggle(js,
      to: dropdown_id,
      in: {"ui-menu-motion", "ui-surface-away", "ui-surface-rest"},
      out: {"ui-menu-motion", "ui-surface-rest", "ui-surface-away"},
      time: 300
    )
  end

  def show_dropdown(js \\ %JS{}, dropdown_id) do
    JS.show(js,
      to: dropdown_id,
      transition: {"ui-menu-motion", "ui-surface-away", "ui-surface-rest"},
      time: 300
    )
  end

  def hide_dropdown(js \\ %JS{}, dropdown_id) do
    JS.hide(js,
      to: dropdown_id,
      transition: {"ui-menu-motion", "ui-surface-rest", "ui-surface-away"},
      time: 300
    )
  end

  # The client reads the motion preference at the time of the action and can
  # reverse an in-flight animation. A hide blocks patch removal only until the
  # client calls the dispatch's done callback (immediate with reduced motion).
  def show_modal(js \\ %JS{}, modal_id) do
    JS.dispatch(js, "b:ui-surface", to: modal_id, detail: %{kind: "modal", action: "show"})
  end

  def hide_modal(js \\ %JS{}, modal_id) do
    JS.dispatch(js, "b:ui-surface", to: modal_id, detail: %{kind: "modal", action: "hide"}, blocking: true)
  end

  def toggle_drawer(js \\ %JS{}, drawer_id) do
    JS.dispatch(js, "b:ui-surface", to: drawer_id, detail: %{kind: "drawer", action: "toggle"})
  end

  # Open the image editor, marking it busy for the wait the drawer itself hides.
  #
  # The same click shows the drawer and asks the server for the editor's payload,
  # and the image still has to be fetched and decoded after that answer arrives.
  # Until then the canvas holds whatever was last opened in it, and a click on
  # that canvas is undone by the re-init. Setting this here rather than in the
  # hook covers the round trip as well: the hook only learns about the new image
  # when the payload lands. The hook clears it once the image is on the canvas.
  def open_image_editor_drawer(js \\ %JS{}) do
    js
    |> JS.set_attribute({"aria-busy", "true"}, to: "#image-editor-hook")
    |> toggle_drawer("#image-editor-drawer")
  end
end
