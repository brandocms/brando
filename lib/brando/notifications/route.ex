defmodule Brando.Notifications.Route do
  @moduledoc """
  Where a site environment's notifications go: a Slack or Microsoft Teams
  incoming webhook, or email to chosen users. See `Brando.Notifications`.

  `events` names what the route sends (at least one); `entry_types` limits
  the events about entries to those content types, empty meaning all. A
  webhook URL is a secret, kept only encrypted (`Brando.Crypto`, bound to the
  route's id); `url` is a virtual field for the form and never loaded.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Brando.Webhooks.URLGuard

  @kinds [:slack, :teams, :email]
  @events ~w(mention scheduled_publish scheduled_unpublish failed_job)
  @paused_reasons [:manual, :failures, :environment_copy]

  @type t :: %__MODULE__{}

  schema "notification_routes" do
    field :name, :string
    field :kind, Ecto.Enum, values: @kinds
    field :events, {:array, :string}, default: []
    field :entry_types, {:array, :string}, default: []
    field :recipient_ids, {:array, :integer}, default: []
    field :url, :string, virtual: true, redact: true
    field :url_ciphertext, :string, redact: true
    field :url_hint, :string
    field :active, :boolean, default: true
    field :paused_reason, Ecto.Enum, values: @paused_reasons
    field :paused_at, :utc_datetime_usec
    field :failing_since, :utc_datetime_usec
    field :last_delivery_at, :utc_datetime_usec
    field :last_delivery_state, :string
    belongs_to :creator, Brando.Users.User

    has_many :deliveries, Brando.Notifications.Delivery

    timestamps(type: :utc_datetime_usec)
  end

  @doc "The destinations: `:slack`, `:teams` and `:email`."
  def kinds, do: @kinds

  @doc "The events a route can send."
  def events, do: @events

  def paused_reasons, do: @paused_reasons

  @doc """
  The fields a person edits. A Slack or Teams route needs a URL when it is
  created or its kind changes; an email route needs at least one recipient.
  Options: `:entry_types` and `:recipient_ids` (the values allowed),
  `:resolve` (look the URL's host up, default true) and `:resolver`.
  """
  def changeset(route, attrs, opts \\ []) do
    route
    |> cast(attrs, [:name, :kind, :events, :entry_types, :recipient_ids, :url])
    # An emptied field casts to nil
    |> update_change(:name, &(&1 && String.trim(&1)))
    |> update_change(:url, &(&1 && String.trim(&1)))
    |> validate_required([:name, :kind])
    |> validate_length(:name, max: 120)
    |> validate_length(:url, max: 2000)
    |> validate_chosen(:events)
    |> validate_subset(:events, @events)
    |> validate_subset(:entry_types, Keyword.get_lazy(opts, :entry_types, &Brando.Webhooks.entry_type_values/0))
    |> validate_recipients(opts)
    |> validate_destination(opts)
  end

  # At least one, also when the field is left as it was (empty)
  defp validate_chosen(changeset, field) do
    if get_field(changeset, field) in [nil, []],
      do: add_error(changeset, field, "should have at least one item", validation: :length, kind: :min, count: 1),
      else: changeset
  end

  defp validate_recipients(changeset, opts) do
    case Keyword.fetch(opts, :recipient_ids) do
      {:ok, allowed} -> validate_subset(changeset, :recipient_ids, allowed)
      :error -> changeset
    end
  end

  defp validate_destination(changeset, opts) do
    case get_field(changeset, :kind) do
      :email ->
        changeset
        |> put_change(:url, nil)
        |> validate_chosen(:recipient_ids)

      kind when kind in [:slack, :teams] ->
        changeset
        |> put_change(:recipient_ids, [])
        |> require_url()
        |> validate_url(opts)

      _ ->
        changeset
    end
  end

  # A saved route keeps its URL unless a new one is given, unless the kind
  # changed: a Slack URL is no use to Teams.
  defp require_url(changeset) do
    needs_url? = is_nil(changeset.data.url_ciphertext) or changed?(changeset, :kind)
    if needs_url?, do: validate_required(changeset, [:url]), else: changeset
  end

  defp validate_url(changeset, opts) do
    case fetch_change(changeset, :url) do
      {:ok, url} when is_binary(url) ->
        check =
          if Keyword.get(opts, :resolve, true),
            do: URLGuard.resolve(url, Keyword.take(opts, [:resolver])),
            else: URLGuard.validate(url)

        case check do
          {:ok, _target} -> changeset
          {:error, reason} -> add_error(changeset, :url, Brando.Webhooks.Webhook.url_error(reason), reason: reason)
        end

      _ ->
        changeset
    end
  end

  @doc """
  Whether `route` sends `event` about an entry of `entry_type`. An event
  that is not about an entry (a failed job) passes any content-type filter.
  """
  def matches?(%__MODULE__{events: events, entry_types: entry_types}, event, entry_type) do
    event in events and (entry_types == [] or is_nil(entry_type) or entry_type in entry_types)
  end
end
