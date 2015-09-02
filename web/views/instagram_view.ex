defmodule Brando.Admin.InstagramView do
  @moduledoc """
  View for the Brando Instagram module.
  """
  use Linguist.Vocabulary
  use Brando.Web, :view

  def show_grouped_images(language, images) do
    approved_header =
      ~s(<h3 class="negative">#{t!(language, "actions.approved")}</h3>) <>
      ~s(<div class="image-selection-pool approved">)
    rejected_header =
      ~s(<h3 class="negative">#{t!(language, "actions.rejected")}</h3>) <>
      ~s(<div class="image-selection-pool rejected">)
    deleted_header =
      ~s(<h3 class="negative">#{t!(language, "actions.deleted")}</h3>) <>
      ~s(<div class="image-selection-pool deleted">)
    failed_header =
      ~s(<h3 class="negative">#{t!(language, "actions.failed")}</h3>) <>
      ~s(<div class="image-selection-pool failed">)
    div_close =
      ~s(</div>)
    prefix = media_url()

    {_, {approved, rejected, deleted, failed}} =
      Enum.map_reduce images, {"", "", "", 0}, fn(i, {a, r, d, f}) ->
      case i.status do
        :approved ->
          a = a <> ~s(<img data-id="#{i.id}" data-status="#{i.status}" ) <>
                   ~s(src="#{img_url(i.image, :thumb, prefix: prefix)}" />)
        :rejected ->
          r = r <> ~s(<img data-id="#{i.id}" data-status="#{i.status}" ) <>
                   ~s(src="#{img_url(i.image, :thumb, prefix: prefix)}" />)
        :deleted ->
          d = d <> ~s(<img data-id="#{i.id}" data-status="#{i.status}" ) <>
                   ~s(src="#{img_url(i.image, :thumb, prefix: prefix)}" />)
        :download_failed ->
          f = f + 1
      end
      {i, {a, r, d, f}}
    end
    failed = ~s(#{failed} #{t!(language, "actions.failed")})
    Enum.join([approved_header, approved, div_close, rejected_header, rejected,
               div_close, deleted_header, deleted, div_close, failed_header,
               failed, div_close])
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
      help1: ~s(Index of instagram images. Only photos in the "approved"-) <>
             ~s(row will be displayed on the webpage.),
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
      help1: ~s(Oversikt over Instagram-bilder. Kun bilder i "godkjent"-) <>
             ~s(raden vil vises på nettsiden.),
      help2: "For å utføre handlinger, velg bilder og klikk deretter på " <>
             "knappen med ønsket handling."
    ]
  ]
end
