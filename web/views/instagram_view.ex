defmodule Brando.Admin.InstagramView do
  @moduledoc """
  View for the Brando Instagram module.
  """
  use Brando.Web, :view
  import Brando.Gettext

  def show_grouped_images(images) do
    approved_header =
      ~s(<h3 class="negative">#{gettext("Approved")}</h3>) <>
      ~s(<div class="image-selection-pool approved">)
    rejected_header =
      ~s(<h3 class="negative">#{gettext("Rejected")}</h3>) <>
      ~s(<div class="image-selection-pool rejected">)
    deleted_header =
      ~s(<h3 class="negative">#{gettext("Deleted")}</h3>) <>
      ~s(<div class="image-selection-pool deleted">)
    failed_header =
      ~s(<h3 class="negative">#{gettext("Download failed")}</h3>) <>
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
    failed = ~s(#{failed} #{gettext("Download failed")})

    Enum.join([
      approved_header, approved, div_close, rejected_header,
      rejected, div_close, deleted_header, deleted, div_close,
      failed_header, failed, div_close]
    ) |> raw
  end
end
