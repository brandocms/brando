defmodule Brando.Notes.Note do
  @moduledoc """
  A note on an entry, or a reply to one (`parent_id`). See `Brando.Notes`.

  A thread's first note carries the anchor: the entry alone, a block
  (`block_uid`), a field (`field_path`, an entry field or, with a block, a
  field inside it) and optionally a text range (`range`, with the quoted
  text). `anchor_label` names the anchor as it was when the note was written,
  so a detached note can still say where it was. Replies carry none of it.

  `detached_at` is set while the anchored block is missing from the saved
  entry, and `text_removed_at` while the marked text is; both clear again if
  a revision brings it back.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "entry_notes" do
    field :entry_type, :string
    field :entry_id, :integer
    field :block_uid, :string
    field :field_path, :string
    field :range, :map
    field :anchor_label, :string
    field :body, :string
    field :resolved_at, :utc_datetime_usec
    field :detached_at, :utc_datetime_usec
    field :text_removed_at, :utc_datetime_usec
    field :deleted_at, :utc_datetime_usec

    belongs_to :parent, __MODULE__
    belongs_to :author, Brando.Users.User
    belongs_to :resolved_by, Brando.Users.User
    has_many :replies, __MODULE__, foreign_key: :parent_id
    has_many :mentions, Brando.Notes.Mention

    timestamps(type: :utc_datetime_usec)
  end

  @max_body 10_000

  @doc "A new thread on an entry."
  def thread_changeset(note, attrs) do
    note
    |> cast(attrs, [:entry_type, :entry_id, :block_uid, :field_path, :range, :anchor_label, :body, :author_id])
    |> update_change(:body, &String.trim/1)
    |> update_change(:anchor_label, &trim_label/1)
    |> validate_required([:entry_type, :entry_id, :body])
    |> validate_length(:body, max: @max_body)
    |> validate_length(:block_uid, max: 255)
    |> validate_length(:field_path, max: 255)
    |> validate_range()
  end

  @doc "A reply in `thread`."
  def reply_changeset(note, %__MODULE__{} = thread, attrs) do
    note
    |> cast(attrs, [:body, :author_id])
    |> update_change(:body, &String.trim/1)
    |> put_change(:entry_type, thread.entry_type)
    |> put_change(:entry_id, thread.entry_id)
    |> put_change(:parent_id, thread.id)
    |> validate_required([:body])
    |> validate_length(:body, max: @max_body)
  end

  defp trim_label(nil), do: nil
  defp trim_label(label), do: label |> String.trim() |> String.slice(0, 200)

  # A range is `%{"quote" => text}`: the text that was marked.
  defp validate_range(changeset) do
    case get_change(changeset, :range) do
      nil ->
        changeset

      %{"quote" => text} when is_binary(text) ->
        put_change(changeset, :range, %{"quote" => String.slice(text, 0, 500)})

      _ ->
        add_error(changeset, :range, "is invalid")
    end
  end

  @doc "Whether the thread is resolved."
  def resolved?(%__MODULE__{resolved_at: resolved_at}), do: not is_nil(resolved_at)
end
