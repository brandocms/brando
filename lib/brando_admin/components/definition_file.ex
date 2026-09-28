defmodule BrandoAdmin.Components.DefinitionFile do
  @moduledoc """
  Shows that a module is also edited as a definition file, when the dev
  watcher runs (see `Brando.Content.Definition.Watcher`), and warns when the
  admin and the file have drifted apart.
  """
  use BrandoAdmin, :component
  use Gettext, backend: Brando.Gettext

  attr :file, :map, required: true

  @doc "A one-line marker for a listing row"
  def marker(%{file: nil} = assigns), do: ~H""

  def marker(assigns) do
    ~H"""
    <span class="definition-file-marker" data-state={@file.state} title={explanation(@file.state)}>
      <.icon name={icon_name(@file.state)} />
      <span :if={@file.state == :in_sync} class="definition-file-path">{@file.name}</span>
      <span :if={@file.state != :in_sync}>{headline(@file.state)}</span>
    </span>
    """
  end

  attr :file, :map, required: true

  @doc "A notice at the top of the module editor"
  def notice(%{file: nil} = assigns), do: ~H""

  def notice(assigns) do
    assigns = assign(assigns, :editor_url, editor_url(assigns.file.absolute))

    ~H"""
    <div class="definition-file-notice" data-state={@file.state} role={@file.state != :in_sync && "alert"}>
      <.icon name={icon_name(@file.state)} />
      <p class="definition-file-headline">
        {if @file.state == :in_sync, do: gettext("This module is also a file"), else: headline(@file.state)}
      </p>
      <a :if={@editor_url} class="definition-file-path" href={@editor_url} title={@file.path}>{@file.name}</a>
      <span :if={!@editor_url} class="definition-file-path" title={@file.path}>{@file.name}</span>
      <p class="definition-file-explanation">{explanation(@file.state)}</p>
    </div>
    """
  end

  defp icon_name(:in_sync), do: "hero-document-text"
  defp icon_name(_), do: "hero-exclamation-triangle"

  defp headline(:pending), do: gettext("File not imported")
  defp headline(:changed_in_admin), do: gettext("Changed here since the file")
  defp headline(:changed_in_both), do: gettext("Changed here and in the file")

  defp explanation(:in_sync),
    do: gettext("Saving the file imports it. Changes made here put the file out of date, so edit the file instead.")

  defp explanation(:pending),
    do:
      gettext(
        "The file has changes that are not imported. The server log says why — usually a change that needs a migration."
      )

  defp explanation(:changed_in_admin),
    do:
      gettext(
        "This module changed in the admin after the file was imported, so the file's next save is refused. Export the modules again to bring the changes into the file before editing it."
      )

  defp explanation(:changed_in_both),
    do:
      gettext(
        "Both this module and its file changed since the last import, so the file is not imported. Export the modules again and reapply your file edits."
      )

  # Phoenix's own convention for "open in editor" links on its error pages,
  # e.g. PLUG_EDITOR="vscode://file/__FILE__:__LINE__"
  defp editor_url(path) do
    case System.get_env("PLUG_EDITOR") do
      editor when editor in [nil, ""] -> nil
      editor -> editor |> String.replace("__FILE__", URI.encode(path)) |> String.replace("__LINE__", "1")
    end
  end
end
