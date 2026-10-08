defmodule Brando.Webhooks do
  @moduledoc """
  Outbound webhooks: signed HTTP POSTs to other systems when content
  changes, built on `Brando.ContentEvents`.

  Webhooks belong to a site environment: their tables live in its schema,
  so a webhook, its deliveries and every id a screen receives are looked up
  in the current environment only. Copying an environment, or restoring an
  archive as a new one, pauses the copy's webhooks
  (`after_environment_copy/2`), so a staging copy never calls production
  endpoints. When that environment goes live, they resume
  (`after_going_live/2`); webhooks paused for another reason stay paused.

  Managing webhooks needs the Webhooks permission (`brando.webhooks.manage`)
  with group authorization, or the admin or superuser role without it. It
  shows content metadata (type, id, URL, status, changed field names) for
  every content type, drafts included, since a webhook sends them to a URL
  its manager chooses. The
  admin screens also ask for the password again (`BrandoAdmin.Reauth`)
  before anything changes.

  ## The request

      POST <url>
      Content-Type: application/json
      User-Agent: Brando-Webhooks
      Brando-Event: entry.published
      Brando-Delivery: 2b0e8d4c-…
      Brando-Signature: t=1791456000,v1=5257a869…

      {
        "delivery_id": "2b0e8d4c-…",
        "event": "entry.published",
        "event_id": "c0a4c3f2-…",
        "occurred_at": "2026-10-08T10:58:12.401Z",
        "site": "shop",
        "environment": "production",
        "entry": {
          "type": "projects.project",
          "id": 42,
          "language": "en",
          "url": "https://example.com/projects/the-house",
          "status": "published",
          "changed_fields": ["status", "title"]
        },
        "actor": {"kind": "person"}
      }

  No entry content and no user details: receivers that need the entry fetch
  it through the site's API. "Send test event" posts `"event": "webhook.test"`
  with `"entry": null`. See `Brando.Webhooks.Signature` for the signature.

  ## Delivery

  Each delivery is an Oban job on the `:webhooks` queue
  (`Brando.Worker.WebhookDelivery`). A response other than 2xx, a timeout
  (10 seconds) or a refused connection is retried with exponential backoff
  for about 24 hours (15 attempts); redirects are not followed. A webhook
  whose delivery has failed for that long is paused, and the dashboard tells
  the people who manage webhooks. At most `concurrency` deliveries to one
  webhook run at a time (default 2), so a slow receiver cannot hold the
  whole queue, and at most `site_concurrency` (default 3) to all the webhooks
  of one site environment, so one site cannot hold the queue every site
  shares. Only `https` URLs on public addresses are called (see
  `Brando.Webhooks.URLGuard`), checked again before every delivery.

  ## Secrets

  A secret is shown once, when the webhook is created or its secret
  rotated. It is stored encrypted (`Brando.Crypto`, bound to the webhook's
  id) and is never logged, written to Activity or kept in the admin's
  LiveView state. Rotating it invalidates the old secret at once — there is
  no overlap — so pause the webhook, rotate, update the receiver, and resume.

  ## Configuration

      config :brando, Brando.Webhooks,
        enabled: true,
        retention_days: 30,
        concurrency: 2,
        site_concurrency: 3,
        # development only: http and loopback addresses
        allow_localhost: false

  The delivery log keeps `retention_days` of deliveries
  (`Brando.Worker.WebhookDeliveryPurger`, nightly).
  """

  import Ecto.Query

  alias Brando.Activity
  alias Brando.Authorization.Boundary
  alias Brando.ContentEvents.Event
  alias Brando.Repo
  alias Brando.Tenant.Job, as: TenantJob
  alias Brando.Webhooks.Delivery
  alias Brando.Webhooks.Webhook
  alias Brando.Worker.WebhookDelivery

  require Logger

  @behaviour Brando.ContentEvents.Subscriber

  @default_retention_days 30
  @default_concurrency 2
  @default_site_concurrency 3
  @test_event "webhook.test"

  ## Configuration

  @doc "Whether webhooks are sent at all."
  def enabled?, do: Keyword.get(config(), :enabled, true)

  @doc "How many days the delivery log keeps."
  def retention_days, do: Keyword.get(config(), :retention_days, @default_retention_days)

  @doc "How many deliveries to one webhook may run at once."
  def concurrency, do: Keyword.get(config(), :concurrency, @default_concurrency)

  @doc "How many deliveries to all the webhooks of one site environment may run at once."
  def site_concurrency, do: Keyword.get(config(), :site_concurrency, @default_site_concurrency)

  defp config, do: Brando.config(__MODULE__) || []

  @doc "The event a test delivery carries."
  def test_event, do: @test_event

  ## Authorization

  @doc """
  Whether `user` may manage webhooks: the `brando.webhooks.manage`
  permission with group authorization, the admin or superuser role without.
  """
  def can_manage?(:system), do: true

  def can_manage?(user) do
    if Brando.Authorization.enabled?(),
      do: Boundary.authorize(user, :manage, :webhooks) == :ok,
      else: match?(%{role: role} when role in [:admin, :superuser], user)
  end

  defp authorize(user), do: if(can_manage?(user), do: :ok, else: {:error, :forbidden})

  ## Choices

  @doc """
  The content types a webhook can be limited to: the blueprints in the
  Content section of the permissions, and menus and global sets. Without a
  limit a webhook gets events for every blueprint Activity logs.
  """
  def entry_schemas do
    Brando.Authorization.Catalog.schemas()
    |> Enum.filter(fn schema ->
      Activity.logged?(schema) and schema != Brando.Users.User and
        (schema in [Brando.Navigation.Menu, Brando.Sites.GlobalSet] or content_section?(schema))
    end)
  rescue
    _ -> []
  end

  defp content_section?(schema) do
    match?([%{section: "Content"} | _], Brando.Authorization.Catalog.for_schema(schema))
  end

  @doc "The `entry_type` values of `entry_schemas/0`."
  def entry_type_values, do: entry_schemas() |> Enum.map(&Event.entry_type/1) |> Enum.reject(&is_nil/1)

  @doc "The site's languages, the default first."
  def language_values do
    default = Brando.config(:default_language)
    configured = Enum.map(Brando.config(:languages) || [], & &1[:value])

    [default | configured]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
    |> Enum.uniq()
  end

  ## Webhooks

  @doc "The webhooks of the current environment, by name."
  def list_webhooks do
    Repo.all(from(w in Webhook, order_by: [asc: fragment("lower(?)", w.name), asc: w.id]))
  end

  @doc "A webhook of the current environment."
  def get_webhook(id) do
    with {:ok, id} <- cast_id(id),
         %Webhook{} = webhook <- Repo.get(Webhook, id) do
      {:ok, webhook}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "A changeset for the webhook form."
  def change_webhook(webhook \\ %Webhook{}, attrs \\ %{}, opts \\ []), do: Webhook.changeset(webhook, attrs, opts)

  @doc """
  Create a webhook with a new secret. Returns the secret once, alongside the
  webhook; it cannot be read back later.
  """
  def create_webhook(attrs, user, opts \\ []) do
    with :ok <- authorize(user) do
      secret = generate_secret()

      fn -> insert_with_secret(attrs, user, opts, secret) end
      |> Repo.transaction()
      |> case do
        {:ok, {webhook, secret}} ->
          broadcast(:changed)
          {:ok, webhook, secret}

        {:error, _} = error ->
          error
      end
    end
  end

  # The secret is bound to the webhook's id, so it is stored after the insert.
  defp insert_with_secret(attrs, user, opts, secret) do
    changeset =
      %Webhook{creator_id: user_id(user)}
      |> Webhook.changeset(attrs, opts)
      |> Ecto.Changeset.put_change(:secret_ciphertext, "")

    with {:ok, webhook} <- Repo.insert(changeset),
         {:ok, webhook} <- store_secret(webhook, secret) do
      Activity.setting_changed(:created, webhook, webhook.name, user, details: %{"url_host" => host(webhook)})
      {webhook, secret}
    else
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  @doc "Change a webhook's name, URL, events or filters."
  def update_webhook(%Webhook{} = webhook, attrs, user, opts \\ []) do
    with :ok <- authorize(user),
         changeset = Webhook.changeset(webhook, attrs, opts),
         {:ok, updated} <- Repo.update(changeset) do
      fields = changeset.changes |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort()
      if fields != [], do: Activity.setting_changed(:updated, updated, updated.name, user, fields: fields)
      broadcast(:changed)
      {:ok, updated}
    end
  end

  @doc "Delete a webhook and its delivery log."
  def delete_webhook(%Webhook{} = webhook, user) do
    with :ok <- authorize(user),
         {:ok, deleted} <- Repo.delete(webhook) do
      Activity.setting_changed(:deleted, deleted, deleted.name, user)
      broadcast(:changed)
      {:ok, deleted}
    end
  end

  @doc """
  Give a webhook a new secret. The old one stops working at once. Returns
  the new secret, once.
  """
  def rotate_secret(%Webhook{} = webhook, user) do
    with :ok <- authorize(user) do
      secret = generate_secret()

      with {:ok, webhook} <- store_secret(webhook, secret, DateTime.utc_now()) do
        Activity.setting_changed(:updated, webhook, webhook.name, user, details: %{"webhook" => "secret_rotated"})
        broadcast(:changed)
        {:ok, webhook, secret}
      end
    end
  end

  @doc "Stop sending to a webhook. `reason` is `:manual`, `:failures` or `:environment_copy`."
  def pause(%Webhook{} = webhook, reason \\ :manual, user) do
    with :ok <- authorize(user),
         {:ok, webhook} <-
           webhook
           |> Ecto.Changeset.change(active: false, paused_reason: reason, paused_at: DateTime.utc_now())
           |> Repo.update() do
      Activity.setting_changed(:updated, webhook, webhook.name, user,
        fields: ["active"],
        details: %{"webhook" => "paused", "reason" => to_string(reason)}
      )

      broadcast(:changed)
      {:ok, webhook}
    end
  end

  @doc "Send to a paused webhook again. Deliveries it missed are not sent; redeliver them from the log."
  def resume(%Webhook{} = webhook, user) do
    with :ok <- authorize(user),
         {:ok, webhook} <-
           webhook
           |> Ecto.Changeset.change(active: true, paused_reason: nil, paused_at: nil, failing_since: nil)
           |> Repo.update() do
      Activity.setting_changed(:updated, webhook, webhook.name, user,
        fields: ["active"],
        details: %{"webhook" => "resumed"}
      )

      broadcast(:changed)
      {:ok, webhook}
    end
  end

  ## Secrets

  defp generate_secret, do: "whsec_" <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

  defp secret_context(%Webhook{id: id}), do: "webhooks.secret:#{id}"

  defp store_secret(webhook, secret, rotated_at \\ nil) do
    webhook
    |> Ecto.Changeset.change(
      secret_ciphertext: Brando.Crypto.encrypt(secret, secret_context(webhook)),
      secret_hint: String.slice(secret, -4, 4),
      secret_rotated_at: rotated_at
    )
    |> Repo.update()
  end

  @doc "The webhook's secret, for signing a delivery. Never show or log it."
  def secret(%Webhook{secret_ciphertext: ciphertext} = webhook) do
    case Brando.Crypto.decrypt(ciphertext, secret_context(webhook)) do
      {:ok, secret} -> {:ok, secret}
      :error -> {:error, :secret_unreadable}
    end
  end

  ## Events

  @impl Brando.ContentEvents.Subscriber
  @doc "Queue a delivery of `event` to every active webhook that wants it."
  # Returns `{:error, _}` when a delivery could not be queued, so the
  # dispatcher retries; deliveries already queued for the event are not
  # queued twice.
  def handle_event(%Event{} = event) do
    from(w in Webhook, where: w.active == true)
    |> Repo.all(savepoint())
    |> Enum.filter(&Webhook.matches?(&1, event.type, event.entry_type, event.language))
    |> Enum.map(&queue(&1, event))
    |> Enum.reject(&(&1 == :ok))
    |> case do
      [] -> :ok
      failed -> {:error, {:not_queued, length(failed)}}
    end
  rescue
    # An environment that has not run the `brando_209` migration has no webhooks
    error in Postgrex.Error ->
      if error.postgres[:code] == :undefined_table, do: :ok, else: reraise(error, __STACKTRACE__)
  end

  defp queue(webhook, %Event{} = event) do
    delivery_id = Ecto.UUID.generate()

    attrs = %{
      webhook_id: webhook.id,
      delivery_id: delivery_id,
      event_id: event.id,
      event: event.type,
      entry_schema: event.schema && to_string(event.schema),
      entry_type: event.entry_type,
      entry_id: event.entry_id,
      language: event.language,
      payload: payload(event, delivery_id)
    }

    # The row and its job together, once per webhook and event: a
    # dispatcher that runs again finds the row and queues nothing more.
    in_transaction(fn ->
      %Delivery{}
      |> Ecto.Changeset.change(attrs)
      |> Repo.insert(
        [
          on_conflict: :nothing,
          conflict_target:
            {:unsafe_fragment, "(webhook_id, event_id) WHERE event_id IS NOT NULL AND redelivery_of_id IS NULL"}
        ] ++ savepoint()
      )
      |> case do
        {:ok, %Delivery{id: id} = delivery} when not is_nil(id) -> enqueue(delivery)
        {:ok, existing} -> {:ok, existing}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  # Inside a transaction already (Oban's inline testing mode runs the
  # dispatcher in the save), each query runs in a savepoint instead.
  defp in_transaction(fun) do
    if Repo.repo().in_transaction?() do
      with {:ok, _} <- fun.(), do: :ok
    else
      case Repo.transaction(fn -> rollback_on_error(fun.()) end) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  rescue
    error ->
      Logger.error("[Brando.Webhooks] Could not queue a delivery: " <> Exception.message(error))
      {:error, :not_queued}
  end

  defp rollback_on_error({:error, reason}), do: Repo.rollback(reason)
  defp rollback_on_error(result), do: result

  defp savepoint, do: Brando.ContentEvents.savepoint()

  @doc "The JSON envelope for `event` (see the moduledoc)."
  def payload(%Event{} = event, delivery_id) do
    %{
      "delivery_id" => delivery_id,
      "event" => event.type,
      "event_id" => event.id,
      "occurred_at" => DateTime.to_iso8601(event.occurred_at),
      "site" => event.site,
      "environment" => event.environment,
      "entry" => %{
        "type" => event.entry_type,
        "id" => event.entry_id,
        "language" => event.language,
        "url" => event.url,
        "status" => event.status,
        "changed_fields" => event.changed_fields
      },
      "actor" => %{"kind" => event.actor}
    }
  end

  defp test_payload(delivery_id) do
    {site, environment} = Brando.Worker.ContentEventDispatcher.site_and_environment()

    %{
      "delivery_id" => delivery_id,
      "event" => @test_event,
      "event_id" => nil,
      "occurred_at" => DateTime.to_iso8601(DateTime.utc_now()),
      "site" => site,
      "environment" => environment,
      "entry" => nil,
      "actor" => %{"kind" => "person"}
    }
  end

  defp enqueue(%Delivery{} = delivery) do
    %{"delivery" => delivery.id, "webhook" => delivery.webhook_id}
    |> TenantJob.attach()
    |> WebhookDelivery.new()
    |> Oban.insert()
    |> case do
      {:ok, _job} -> {:ok, delivery}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Send a `webhook.test` event to an active webhook, through the same checks as any delivery."
  def send_test(%Webhook{} = webhook, user) do
    with :ok <- authorize(user),
         :ok <- active(webhook) do
      delivery_id = Ecto.UUID.generate()

      %Delivery{}
      |> Ecto.Changeset.change(%{
        webhook_id: webhook.id,
        delivery_id: delivery_id,
        event: @test_event,
        payload: test_payload(delivery_id),
        test: true
      })
      |> Repo.insert()
      |> case do
        {:ok, delivery} -> enqueue(delivery)
        error -> error
      end
    end
  end

  @doc "Send a delivery again, as a new delivery with its own id and the same event."
  def redeliver(%Delivery{} = original, user) do
    with :ok <- authorize(user),
         {:ok, webhook} <- get_webhook(original.webhook_id),
         :ok <- active(webhook) do
      delivery_id = Ecto.UUID.generate()

      %Delivery{}
      |> Ecto.Changeset.change(%{
        webhook_id: webhook.id,
        delivery_id: delivery_id,
        event_id: original.event_id,
        event: original.event,
        entry_schema: original.entry_schema,
        entry_type: original.entry_type,
        entry_id: original.entry_id,
        language: original.language,
        payload: Map.put(original.payload, "delivery_id", delivery_id),
        test: original.test,
        redelivery_of_id: original.id
      })
      |> Repo.insert()
      |> case do
        {:ok, delivery} -> enqueue(delivery)
        error -> error
      end
    end
  end

  defp active(%Webhook{active: true}), do: :ok
  defp active(_webhook), do: {:error, :paused}

  ## The log

  @doc "A webhook's deliveries, newest first. Options: `:limit` (default 50)."
  def list_deliveries(%Webhook{id: id}, opts \\ []) do
    from(d in Delivery,
      where: d.webhook_id == ^id,
      order_by: [desc: d.inserted_at, desc: d.id],
      limit: ^Keyword.get(opts, :limit, 50)
    )
    |> Repo.all()
  end

  @doc "Deliveries to every webhook of the current environment, newest first, with their webhook."
  def list_all_deliveries(opts \\ []) do
    from(d in Delivery,
      order_by: [desc: d.inserted_at, desc: d.id],
      limit: ^Keyword.get(opts, :limit, 50),
      preload: :webhook
    )
    |> Repo.all()
  end

  @doc "The current titles of the entries `deliveries` name, as `%{{schema, id} => title}`, from their identifiers."
  def entry_titles(deliveries) do
    ids = deliveries |> Enum.map(& &1.entry_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    if ids == [] do
      %{}
    else
      from(i in Brando.Content.Identifier, where: i.entry_id in ^ids, select: {i.schema, i.entry_id, i.title})
      |> Repo.all()
      |> Map.new(fn {schema, id, title} -> {{to_string(schema), id}, title} end)
    end
  rescue
    _ -> %{}
  end

  @doc "A delivery of the current environment."
  def get_delivery(id) do
    with {:ok, id} <- cast_id(id),
         %Delivery{} = delivery <- Repo.get(Delivery, id) do
      {:ok, delivery}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "A delivery of `webhook`."
  def get_delivery(%Webhook{id: webhook_id}, id) do
    with {:ok, id} <- cast_id(id),
         %Delivery{} = delivery <- Repo.get_by(Delivery, id: id, webhook_id: webhook_id) do
      {:ok, delivery}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  For the Integrations screen: how many webhooks there are, the latest
  delivery and its webhook, and how many deliveries failed in the last day.
  """
  def summary do
    since = DateTime.add(DateTime.utc_now(), -86_400, :second)

    latest =
      from(d in Delivery,
        where: d.state in ["succeeded", "retrying", "failed"],
        order_by: [desc: d.completed_at, desc: d.id],
        limit: 1,
        preload: :webhook
      )
      |> Repo.one()

    %{
      count: Repo.aggregate(Webhook, :count),
      latest: latest,
      failed:
        Repo.aggregate(
          from(d in Delivery, where: d.state in ["retrying", "failed"] and d.inserted_at >= ^since),
          :count
        ),
      retrying: Repo.aggregate(from(d in Delivery, where: d.state == "retrying"), :count)
    }
  rescue
    _ -> %{count: 0, latest: nil, failed: 0, retrying: 0}
  end

  @doc "The webhooks paused because their deliveries kept failing, for the dashboard."
  def paused_after_failures do
    Repo.all(from(w in Webhook, where: w.active == false and w.paused_reason == :failures, order_by: w.name))
  rescue
    _ -> []
  end

  @doc "Remove deliveries older than `days`. Returns how many."
  def purge_deliveries(days \\ retention_days()) do
    cutoff = DateTime.add(DateTime.utc_now(), -days * 86_400, :second)
    {count, _} = Repo.delete_all(from(d in Delivery, where: d.inserted_at < ^cutoff))
    count
  end

  @doc """
  After an environment's content was replaced from another schema — copied
  from another environment, or restored from an archive as a new
  environment — its webhooks (the source's) are paused with the reason
  `:environment_copy`, and the delivery log that came along is cleared, so
  the copy calls no endpoint. Webhooks paused for another reason stay as
  they are. `actor` is recorded in Activity.
  """
  def after_environment_copy(prefix, actor \\ :system) do
    if tables?(prefix), do: pause_copied(prefix, actor), else: :ok
  end

  @doc """
  After the environment at `prefix` became the live one: its webhooks paused
  because the environment was a copy are resumed. Webhooks paused after
  failures or by hand stay paused. Returns how many were resumed.
  """
  def after_going_live(prefix, actor \\ :system) do
    if tables?(prefix), do: resume_copied(prefix, actor), else: 0
  end

  defp tables?(prefix) do
    %{rows: [[table]]} = Repo.repo().query!("SELECT to_regclass($1)::text", [~s("#{prefix}".webhooks)])
    not is_nil(table)
  end

  defp pause_copied(prefix, actor) do
    now = DateTime.utc_now()

    {_count, paused} =
      Repo.update_all(
        from(w in Webhook, where: w.active == true, select: w),
        [set: [active: false, paused_reason: :environment_copy, paused_at: now]],
        prefix: prefix
      )

    Repo.delete_all(Delivery, prefix: prefix)

    record_lifecycle(prefix, paused, actor, %{"webhook" => "paused", "reason" => "environment_copy"})
    :ok
  rescue
    error ->
      Logger.error("[Brando.Webhooks] Could not pause the webhooks of #{prefix}: " <> Exception.message(error))
      {:error, :webhooks_not_paused}
  end

  defp resume_copied(prefix, actor) do
    {count, resumed} =
      Repo.update_all(
        from(w in Webhook, where: w.active == false and w.paused_reason == :environment_copy, select: w),
        [set: [active: true, paused_reason: nil, paused_at: nil, failing_since: nil]],
        prefix: prefix
      )

    record_lifecycle(prefix, resumed, actor, %{"webhook" => "resumed", "reason" => "went_live"})
    count
  rescue
    error ->
      Logger.error("[Brando.Webhooks] Could not resume the webhooks of #{prefix}: " <> Exception.message(error))
      0
  end

  defp record_lifecycle(_prefix, [], _actor, _details), do: :ok

  defp record_lifecycle(prefix, webhooks, actor, details) do
    Brando.Tenant.with_prefix(prefix, fn ->
      Enum.each(webhooks, fn webhook ->
        Activity.setting_changed(:updated, webhook, webhook.name, actor, fields: ["active"], details: details)
      end)

      broadcast(:changed)
    end)
  end

  ## Updates for the admin

  @doc "The PubSub topic for webhook changes and deliveries in the current environment."
  def topic(prefix \\ Brando.Tenant.current_prefix())
  def topic(nil), do: "brando:webhooks"
  def topic(prefix), do: "brando:webhooks:" <> prefix

  @doc "Tell the admin screens of the current environment that `message` happened."
  def broadcast(message), do: Phoenix.PubSub.broadcast(Brando.pubsub(), topic(), {__MODULE__, message})

  ## Helpers

  @doc "The host a webhook calls, for showing in lists and the log without the rest of its URL."
  def host(%Webhook{url: url}) do
    case URI.new(url || "") do
      {:ok, %URI{host: host}} when is_binary(host) -> host
      _ -> nil
    end
  end

  defp cast_id(id) when is_integer(id), do: {:ok, id}

  defp cast_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {id, ""} -> {:ok, id}
      _ -> :error
    end
  end

  defp cast_id(_), do: :error

  defp user_id(%{id: id}), do: id
  defp user_id(_), do: nil
end
