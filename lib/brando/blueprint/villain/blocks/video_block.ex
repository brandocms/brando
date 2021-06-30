defmodule Brando.Blueprint.Villain.Blocks.VideoBlock do
  use Ecto.Schema
  import Ecto.Changeset
  alias Brando.Blueprint.Villain.Blocks

  @primary_key false

  embedded_schema do
    field :uid, :string
    field :type, :string
    field :hidden, :boolean, default: false
    field :marked_as_deleted, :boolean, default: false, virtual: true

    embeds_one :data, Brando.Videos.Video
  end

  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, ~w(uid type hidden marked_as_deleted)a)
    |> cast_embed(:data)
  end
end
