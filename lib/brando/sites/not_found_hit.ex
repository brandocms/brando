defmodule Brando.Sites.NotFoundHit do
  @moduledoc """
  One day's 404s for a URL from one referrer (`""` when the request had none).
  Written by `Brando.Sites.FourOhFour`, which keeps the counts in a short
  in-memory buffer and adds them here in batches.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "sites_not_found_hits" do
    field :url, :string
    field :referrer, :string, default: ""
    field :date, :date
    field :hits, :integer, default: 0
    field :last_hit_at, :utc_datetime
  end
end
