defmodule Brando.Admin.InstagramView do
  @moduledoc """
  View for the Brando Instagram module.
  """
  use Brando.Web, :view

  def show_grouped_images(images) do
    require Logger
    approved_header = "<h3 class=\"negative\">Godkjente bilder</h3><div class=\"image-selection-pool approved\">"
    rejected_header = "<h3 class=\"negative\">Avviste bilder</h3><div class=\"image-selection-pool rejected\">"
    deleted_header  = "<h3 class=\"negative\">Slettede bilder</h3><div class=\"image-selection-pool deleted\">"
    div_close       = "</div>"

    {_, {approved, rejected, deleted}} = Enum.map_reduce images, {"", "", ""}, fn(img, {approved, rejected, deleted}) ->
      case img.status do
        :approved ->
          approved = approved <> "<img data-id=\"#{img.id}\" data-status=\"#{img.status}\" src=\"#{media_url(img(img.image, :thumb))}\" />"
        :rejected ->
          rejected = rejected <> "<img data-id=\"#{img.id}\" data-status=\"#{img.status}\" src=\"#{media_url(img(img.image, :thumb))}\" />"
        :deleted ->
          deleted = deleted <> "<img data-id=\"#{img.id}\" data-status=\"#{img.status}\" src=\"#{media_url(img(img.image, :thumb))}\" />"
      end
      {img, {approved, rejected, deleted}}
    end
    html = Enum.join([approved_header, approved, div_close, rejected_header, rejected, div_close, deleted_header, deleted, div_close])
    Phoenix.HTML.raw(html)
  end
end
