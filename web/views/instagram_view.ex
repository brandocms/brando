defmodule Brando.Admin.InstagramView do
  @moduledoc """
  View for the Brando Instagram module.
  """
  use Brando.Web, :view
  import Brando.Gettext

  @approved_header ~s(<h3 class="negative">#{gettext("Approved")}</h3>) <>
                   ~s(<div class="image-selection-pool approved">)
  @rejected_header ~s(<h3 class="negative">#{gettext("Rejected")}</h3>) <>
                   ~s(<div class="image-selection-pool rejected">)
  @deleted_header  ~s(<h3 class="negative">#{gettext("Deleted")}</h3>) <>
                   ~s(<div class="image-selection-pool deleted">)
  @failed_header   ~s(<h3 class="negative">#{gettext("Download failed")}</h3>) <>
                   ~s(<div class="image-selection-pool failed">)
  @div_close       ~s(</div>)

  def show_grouped_images(images) do
    {_, {approved, rejected, deleted, failed}} =
      Enum.map_reduce(images, {"", "", "", 0}, fn(i, data) ->
        check_status(i, data)
      end)
    failed = ~s(#{failed} #{gettext("Download failed")})

    [@approved_header, approved, @div_close, @rejected_header,
     rejected, @div_close, @deleted_header, deleted, @div_close,
     @failed_header, failed, @div_close]
    |> Enum.join
    |> raw
  end

  defp check_status(%{status: :approved} = i, {a, r, d, f}) do
    {i, {a <> ~s(<img data-id="#{i.id}" data-status="#{i.status}" ) <>
             ~s(src="#{img_url(i.image, :thumb, prefix: media_url())}" />), r, d, f}}
  end

  defp check_status(%{status: :rejected} = i, {a, r, d, f}) do
    {i, {a, r <> ~s(<img data-id="#{i.id}" data-status="#{i.status}" ) <>
                 ~s(src="#{img_url(i.image, :thumb, prefix: media_url())}" />), d, f}}
  end

  defp check_status(%{status: :deleted} = i, {a, r, d, f}) do
    {i, {a, r, d <> ~s(<img data-id="#{i.id}" data-status="#{i.status}" ) <>
                    ~s(src="#{img_url(i.image, :thumb, prefix: media_url())}" />), f}}
  end

  defp check_status(%{status: :download_failed} = i, {a, r, d, f}) do
    {i, {a, r, d, f + 1}}
  end
end
