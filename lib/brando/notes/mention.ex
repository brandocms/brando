defmodule Brando.Notes.Mention do
  @moduledoc """
  A user mentioned in a note. `emailed_at` is when the user was emailed about
  it; a mention without it is still to be sent (`Brando.Worker.NoteMentions`).
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "note_mentions" do
    belongs_to :note, Brando.Notes.Note
    belongs_to :user, Brando.Users.User
    field :emailed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
