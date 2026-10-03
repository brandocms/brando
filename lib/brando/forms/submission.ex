defmodule Brando.Forms.Submission do
  @moduledoc """
  What a visitor sent with a `Brando.Forms.Form`.

  Submissions live in `public` (see `Brando.Tenant.SharedTables`), scoped by
  the tenant prefix they were sent in, so promoting an environment — which
  replaces its schema — keeps them. `form_id` is the form in the language it
  was sent in; `form_key` groups a form's languages.

  `data` holds the values by field key; `labels` the field labels at the time,
  so a submission still reads correctly after the form changes.

  When the form has recipients, `queued_at` is set as its notification is
  queued, and `sent_at` once it has gone out, or `send_error` with why not
  (see `Brando.Forms.Notification`).
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @schema_prefix "public"
  schema "forms_submissions" do
    field :scope, :string
    field :form_id, :integer
    field :form_key, :string
    field :language, :string
    field :data, :map, default: %{}
    field :labels, :map, default: %{}
    field :url, :string
    field :ip_hash, :string
    field :user_agent, :string
    field :queued_at, :utc_datetime_usec
    field :sent_at, :utc_datetime_usec
    field :send_error, :string
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc """
  Where the submission's notification stands: `:sent`, `:failed`, `:queued`,
  or nil when none was sent.
  """
  @spec email_status(t()) :: :sent | :failed | :queued | nil
  def email_status(%__MODULE__{send_error: error}) when is_binary(error), do: :failed
  def email_status(%__MODULE__{sent_at: %DateTime{}}), do: :sent
  def email_status(%__MODULE__{queued_at: %DateTime{}}), do: :queued
  def email_status(_submission), do: nil

  @doc "The scope submissions are stored and listed under: the current tenant prefix."
  def current_scope, do: Brando.Tenant.current_prefix() || "public"
end
