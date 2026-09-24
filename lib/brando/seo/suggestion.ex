defmodule Brando.SEO.Suggestion do
  @moduledoc """
  A meta value written by AI for one entry, waiting for an editor's verdict.

  Bulk generation from the Content SEO tab never writes to entries: each job
  fills in one of these, and only accepting it (`Brando.SEO.Suggestions.accept/3`)
  updates the entry. One row per entry, field and language — asking again
  replaces it.

    * `:queued` — a job is on its way
    * `:pending` — written, waiting for review
    * `:accepted` / `:rejected` — reviewed
    * `:failed` — the job gave up; `error` says why

  Not a Blueprint: this is review bookkeeping, with no listing or identifier
  of its own.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @statuses [:queued, :pending, :accepted, :rejected, :failed]
  @fields [:meta_description, :meta_title]

  schema "seo_meta_suggestions" do
    field :schema, :string
    field :entry_id, :integer
    field :language, :string
    field :field, Ecto.Enum, values: @fields
    field :title, :string
    field :text, :string
    field :model, :string
    field :status, Ecto.Enum, values: @statuses, default: :queued
    field :error, :string
    field :generated_at, :utc_datetime

    belongs_to :requested_by, Brando.Users.User
    belongs_to :reviewed_by, Brando.Users.User

    timestamps()
  end

  def changeset(suggestion \\ %__MODULE__{}, attrs) do
    suggestion
    |> cast(attrs, [
      :schema,
      :entry_id,
      :language,
      :field,
      :title,
      :text,
      :model,
      :status,
      :error,
      :generated_at,
      :requested_by_id,
      :reviewed_by_id
    ])
    |> validate_required([:schema, :entry_id, :language, :field, :status])
    |> unique_constraint([:schema, :entry_id, :language, :field])
  end

  @doc "The blueprint module a suggestion belongs to, or `nil` if it no longer exists."
  @spec schema_module(t()) :: module() | nil
  def schema_module(%__MODULE__{schema: schema}) do
    module = String.to_existing_atom("Elixir." <> schema)
    if Code.ensure_loaded?(module), do: module
  rescue
    ArgumentError -> nil
  end
end
