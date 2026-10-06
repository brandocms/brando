defmodule Brando.Repo.Migrations.FixGalleryRefsInModules do
  use Ecto.Migration

  @moduledoc """
  Superseded by `brando_200`.

  This migration renamed loops written directly over a gallery ref
  (`{% for image in refs.slider.gallery.gallery_objects %}`) to
  `gallery_object` and rewrote the loop body line by line. It rewrote HTML as
  well (`class="image"` became `class="gallery_object.image"`), and it lost the
  loop at the first nested `{% endfor %}`, leaving later lines on a variable
  that no longer existed.

  `brando_200` repairs these loops, and loops over a list assigned from a
  gallery ref, inside Liquid only. Module code this migration already
  converted reads `gallery_object.image`, which `brando_200` leaves alone.
  """

  def change, do: :ok
end
