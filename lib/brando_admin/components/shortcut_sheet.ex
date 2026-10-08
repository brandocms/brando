defmodule BrandoAdmin.Components.ShortcutSheet do
  @moduledoc """
  The keyboard shortcut sheet: a modal dialog listing the admin's shortcuts,
  in groups. `?` opens it, and so do "Keyboard shortcuts" in the command
  palette and in the user menu.

  The shortcuts themselves are in `assets/src/shortcuts/registry.js`, and the
  `Brando.ShortcutSheet` hook draws the rows from there each time the sheet
  opens. This module renders the dialog and gives the hook its translated
  text: `labels/0`, a label per shortcut id, group and key name. Every id in
  the registry has a label here (`test/brando_admin/components/shortcut_sheet_test.exs`).

  The switch at the foot turns single-key shortcuts (`?`, `g` then `d`, `f`,
  `c`) off in this browser, for anyone they get in the way of, such as a
  screen reader user (WCAG 2.1.4). The sheet stays a click away in the
  palette and the user menu.
  """
  use Phoenix.Component
  use Gettext, backend: Brando.Gettext

  alias Phoenix.LiveView.JS

  @doc "The sheet's text, keyed by shortcut id, `group_<group>` and `key_<name>`."
  def labels do
    %{
      "group_global" => gettext("Global"),
      "group_listing" => gettext("Listing"),
      "group_entry" => gettext("Entry editor"),
      "group_block" => gettext("Block editor"),
      "help" => gettext("Show keyboard shortcuts"),
      "palette" => gettext("Search and commands"),
      "go-dashboard" => gettext("Go to Dashboard"),
      "go-search" => gettext("Go to Search"),
      "go-assistant" => gettext("Go to Assistant"),
      "go-configuration" => gettext("Go to Configuration"),
      "go-images" => gettext("Go to Images"),
      "go-users" => gettext("Go to Users"),
      "menu-move" => gettext("Move through a menu or list"),
      "close" => gettext("Close a dialog or menu"),
      "filter" => gettext("Filter the list"),
      "new-entry" => gettext("Create an entry"),
      "save" => gettext("Save and continue editing"),
      "save-close" => gettext("Save and close"),
      "preview" => gettext("Open or close the live preview"),
      "bold" => gettext("Bold"),
      "italic" => gettext("Italic"),
      "rich-text-toolbar" => gettext("Move to the rich text toolbar"),
      "add-note" => gettext("Add a note on the selected text"),
      "module-picker-move" => gettext("Move through the module picker's results"),
      "module-picker-insert" => gettext("Insert the marked module"),
      "then" => gettext("then"),
      "or" => gettext("or"),
      "key_command" => gettext("Command"),
      "key_shift" => gettext("Shift"),
      "key_option" => gettext("Option"),
      "key_control" => gettext("Control"),
      "key_ctrl" => gettext("Ctrl"),
      "key_alt" => gettext("Alt"),
      "key_up" => gettext("Up arrow"),
      "key_down" => gettext("Down arrow"),
      "key_enter" => gettext("Enter"),
      "key_escape" => gettext("Escape")
    }
  end

  def render(assigns) do
    assigns = assign(assigns, :labels, Jason.encode!(labels()))

    ~H"""
    <dialog
      id="shortcut-sheet"
      class="shortcut-sheet"
      aria-labelledby="shortcut-sheet-title"
      phx-hook="Brando.ShortcutSheet"
      phx-mounted={JS.ignore_attributes(["open"])}
      data-labels={@labels}
    >
      <header class="shortcut-sheet-header">
        <h2 id="shortcut-sheet-title" tabindex="-1">{gettext("Keyboard shortcuts")}</h2>
        <button type="button" class="shortcut-sheet-close" data-shortcut-sheet-close aria-label={gettext("Close")}>
          <kbd>esc</kbd>
        </button>
      </header>
      <div id="shortcut-sheet-body" class="shortcut-sheet-body" phx-update="ignore" data-shortcut-sheet-body></div>
      <footer id="shortcut-sheet-footer" class="shortcut-sheet-footer" phx-update="ignore">
        <label class="shortcut-sheet-setting">
          <input
            type="checkbox"
            checked
            data-shortcut-sheet-character-keys
            aria-describedby="shortcut-sheet-setting-description"
          />
          <span>{gettext("Single-key shortcuts")}</span>
        </label>
        <p id="shortcut-sheet-setting-description">
          {gettext(
            "Shortcuts typed without a modifier key, such as ? and G then D. Turn them off if they get in the way of a screen reader or speech input. Saved in this browser."
          )}
        </p>
      </footer>
    </dialog>
    """
  end
end
