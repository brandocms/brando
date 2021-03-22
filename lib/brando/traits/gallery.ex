defmodule Brando.Traits.Gallery do
  @moduledoc """

  """
  use Brando.Trait
  alias Ecto.Changeset

  @type changeset :: Changeset.t()
  @type config :: list()

  relations do
    relation :image_series, :belongs_to,
      module: Brando.ImageSeries,
      cast: :with_user
  end
end
