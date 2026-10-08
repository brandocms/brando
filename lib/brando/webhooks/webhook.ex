defmodule Brando.Webhooks.Webhook do
  @moduledoc """
  An endpoint this site environment calls when its content changes. See
  `Brando.Webhooks`.

  `events` and `entry_types` and `languages` limit what is sent; empty means
  all. The signing secret is kept only encrypted (`Brando.Crypto`, bound to
  the webhook's id) and never shows when the struct is inspected.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Brando.Webhooks.URLGuard

  @paused_reasons [:manual, :failures, :environment_copy]

  @type t :: %__MODULE__{}

  schema "webhooks" do
    field :name, :string
    field :url, :string
    field :events, {:array, :string}, default: []
    field :entry_types, {:array, :string}, default: []
    field :languages, {:array, :string}, default: []
    field :active, :boolean, default: true
    field :paused_reason, Ecto.Enum, values: @paused_reasons
    field :paused_at, :utc_datetime_usec
    field :secret_ciphertext, :string, redact: true
    field :secret_hint, :string
    field :secret_rotated_at, :utc_datetime_usec
    field :failing_since, :utc_datetime_usec
    field :last_delivery_at, :utc_datetime_usec
    field :last_delivery_state, :string
    belongs_to :creator, Brando.Users.User

    has_many :deliveries, Brando.Webhooks.Delivery

    timestamps(type: :utc_datetime_usec)
  end

  @doc "The fields a person edits."
  def changeset(webhook, attrs, opts \\ []) do
    webhook
    |> cast(attrs, [:name, :url, :events, :entry_types, :languages])
    # An emptied field casts to nil
    |> update_change(:name, &(&1 && String.trim(&1)))
    |> update_change(:url, &(&1 && String.trim(&1)))
    |> validate_required([:name, :url])
    |> validate_length(:name, max: 120)
    |> validate_length(:url, max: 2000)
    |> validate_subset(:events, Brando.ContentEvents.types())
    |> validate_subset(:entry_types, Keyword.get(opts, :entry_types, Brando.Webhooks.entry_type_values()))
    |> validate_subset(:languages, Keyword.get(opts, :languages, Brando.Webhooks.language_values()))
    |> validate_url(opts)
  end

  # Checked when it changes: the scheme, and every address the host resolves
  # to. `resolve: false` (while typing) checks the URL without looking it up.
  defp validate_url(changeset, opts) do
    case fetch_change(changeset, :url) do
      {:ok, url} when is_binary(url) ->
        check =
          if Keyword.get(opts, :resolve, true),
            do: URLGuard.resolve(url, Keyword.take(opts, [:resolver])),
            else: URLGuard.validate(url)

        case check do
          {:ok, _target} -> changeset
          {:error, reason} -> add_error(changeset, :url, url_error(reason), reason: reason)
        end

      _ ->
        changeset
    end
  end

  @doc false
  def url_error(:https_required), do: "must start with https://"
  def url_error(:scheme_not_allowed), do: "must start with https://"
  def url_error(:credentials_in_url), do: "must not contain a user name or password"
  def url_error(:unresolvable), do: "has a host name that could not be found"
  def url_error(:private_address), do: "points to a private or local network address"
  def url_error(_), do: "is not a valid URL"

  @doc "Whether `webhook` is sent `type` events for an entry of `entry_type` in `language`."
  def matches?(%__MODULE__{} = webhook, type, entry_type, language) do
    included?(webhook.events, type) and included?(webhook.entry_types, entry_type) and
      included?(webhook.languages, language)
  end

  defp included?([], _value), do: true
  defp included?(list, value), do: value in list

  def paused_reasons, do: @paused_reasons
end
