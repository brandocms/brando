defmodule Brando.Admin.InstagramView do
  @moduledoc """
  View for the Brando Instagram module.
  """
  use Brando.Web, :view

  def show_grouped_images(images) do
    require Logger
    {html, _} = Enum.map_reduce images, nil, fn (img, prev) ->
      out = ""
      if prev == nil do
        header = case img.status do
          :approved -> "Godkjente bilder"
          :rejected -> "Avviste bilder"
          :deleted  -> "Slettede bilder"
        end
        out = out <> "<h3 class=\"negative\">#{header}</h3><div class=\"image-selection-pool #{img.status}\">"
      else
        if img.status != prev.status do
          header = case img.status do
            :approved -> "Godkjente bilder"
            :rejected -> "Avviste bilder"
            :deleted  -> "Slettede bilder"
          end
          out = out <> "</div><h3 class=\"negative\">#{header}</h3><div class=\"image-selection-pool #{img.status}\">"
        end
      end
      out = out <> "<img data-id=\"#{img.id}\" data-status=\"#{img.status}\" src=\"#{media_url(img(img.image, :thumb))}\" />"
      {out, img}
    end
    buttons = ~s(<button class="approve-selected-images btn btn-default m-t-md">Merk som godkjent</button>
                 <button class="reject-selected-images btn btn-default m-t-md">Merk som avvist</button>
                 <button class="delete-selected-images btn btn-default m-t-md">Merk som slettet</button>)
    Phoenix.HTML.raw([buttons|html])
  end
end
