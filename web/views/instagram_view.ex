defmodule Brando.Admin.InstagramView do
  @moduledoc """
  View for the Brando Instagram module.
  """
  use Linguist.Vocabulary
  use Brando.Web, :view

  def show_grouped_images(language, images) do
    approved_header = "<h3 class=\"negative\">#{t!(language, "actions.approved")}</h3><div class=\"image-selection-pool approved\">"
    rejected_header = "<h3 class=\"negative\">#{t!(language, "actions.rejected")}</h3><div class=\"image-selection-pool rejected\">"
    deleted_header  = "<h3 class=\"negative\">#{t!(language, "actions.deleted")}</h3><div class=\"image-selection-pool deleted\">"
    failed_header   = "<h3 class=\"negative\">#{t!(language, "actions.failed")}</h3><div class=\"image-selection-pool failed\">"
    div_close       = "</div>"
    prefix          = media_url()

    {_, {approved, rejected, deleted, failed}} = Enum.map_reduce images, {"", "", "", 0}, fn(img, {approved, rejected, deleted, failed}) ->
      case img.status do
        :approved ->
          approved = approved <> "<img data-id=\"#{img.id}\" data-status=\"#{img.status}\" src=\"#{img(img.image, :thumb, prefix: prefix)}\" />"
        :rejected ->
          rejected = rejected <> "<img data-id=\"#{img.id}\" data-status=\"#{img.status}\" src=\"#{img(img.image, :thumb, prefix: prefix)}\" />"
        :deleted ->
          deleted = deleted <> "<img data-id=\"#{img.id}\" data-status=\"#{img.status}\" src=\"#{img(img.image, :thumb, prefix: prefix)}\" />"
        :download_failed ->
          failed = failed + 1
      end
      {img, {approved, rejected, deleted, failed}}
    end
    failed = "#{failed} #{t!(language, "actions.failed")}"
    Enum.join([approved_header, approved, div_close, rejected_header, rejected, div_close, deleted_header, deleted, div_close, failed_header, failed, div_close])
    |> Phoenix.HTML.raw
  end

  locale "en", [
    actions: [
      index: "Index - instagram images",
      new: "New instagram image",
      show: "Show instagram image",
      edit: "Edit instagram image",
      empty: "No instagram images",
      delete: "Delete instagram image",

      approved: "Approved",
      rejected: "Rejected",
      deleted: "Deleted",
      failed: "Download failed",

      mark_as: "Mark as"
    ],
    content: [
      help1: "Index of instagram images. Only photos in the \"approved\"-" <>
             "row will be displayed on the webpage.",
      help2: "Select photos, and click on your wanted action."
    ]
  ]

  locale "no", [
    actions: [
      index: "Oversikt - instagrambilder",
      new: "Opprett instagrambilde",
      show: "Vis instagrambilde",
      edit: "Endre instagrambilde",
      empty: "Ingen instagrambilder",
      delete: "Slett instagrambilde",

      approved: "Godkjent",
      rejected: "Avvist",
      deleted: "Slettet",
      failed: "Nedlasting feilet",

      mark_as: "Merk som"
    ],
    content: [
      help1: "Oversikt over Instagram-bilder. Kun bilder i \"godkjent\"-" <>
             "raden vil vises på nettsiden.",
      help2: "For å utføre handlinger, velg bilder og klikk deretter på " <>
             "knappen med ønsket handling."
    ]
  ]
end
