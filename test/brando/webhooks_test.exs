defmodule Brando.WebhooksTest do
  use ExUnit.Case
  use Brando.ConnCase

  alias Brando.Activity
  alias Brando.Factory
  alias Brando.Pages
  alias Brando.WebhookReceiver
  alias Brando.Webhooks
  alias Brando.Webhooks.Delivery
  alias Brando.Webhooks.Signature
  alias Brando.Webhooks.Webhook
  alias Brando.Worker.ContentEventDispatcher
  alias Brando.Worker.WebhookDelivery

  @resolver {Brando.WebhookTestResolver, :resolve}

  setup do
    # The fake receiver listens on loopback, which only the development
    # override allows.
    put_test_env(Brando.Webhooks, allow_localhost: true, resolver: @resolver)
    put_test_env(Brando.ContentEvents, debounce_seconds: 0)
    user = Factory.insert(:random_user)
    {:ok, %{user: user}}
  end

  defp create_webhook(user, url, attrs \\ %{}) do
    {:ok, webhook, secret} = Webhooks.create_webhook(Map.merge(%{"name" => "Shop cache", "url" => url}, attrs), user)
    {webhook, secret}
  end

  defp create_page(user, attrs \\ %{}) do
    {:ok, page} =
      Pages.create_page(
        Map.merge(
          %{
            title: "Top secret launch",
            uri: "launch-#{System.unique_integer([:positive])}",
            language: "en",
            template: "default.html",
            status: :draft
          },
          attrs
        ),
        user
      )

    page
  end

  defp deliveries(webhook), do: Webhooks.list_deliveries(webhook)

  defp next_request do
    assert_receive {:webhook_request, request}, 5_000
    request
  end

  describe "secrets" do
    test "are shown once, kept encrypted and bound to the webhook", %{user: user} do
      receiver = WebhookReceiver.start()
      {webhook, secret} = create_webhook(user, WebhookReceiver.url(receiver))

      assert "whsec_" <> _ = secret
      assert byte_size(secret) > 40

      stored = Repo.get!(Webhook, webhook.id)
      refute stored.secret_ciphertext =~ secret
      assert stored.secret_hint == String.slice(secret, -4, 4)
      assert Webhooks.secret(stored) == {:ok, secret}

      # Copied to another webhook's row, it does not decrypt
      assert :error = Brando.Crypto.decrypt(stored.secret_ciphertext, "webhooks.secret:#{webhook.id + 1}")
      assert {:error, :secret_unreadable} = Webhooks.secret(%{stored | id: webhook.id + 1})
    end

    test "never show in inspect, logs or Activity", %{user: user} do
      receiver = WebhookReceiver.start()

      log =
        ExUnit.CaptureLog.capture_log([level: :debug], fn ->
          {webhook, secret} = create_webhook(user, WebhookReceiver.url(receiver))
          {:ok, _webhook, rotated} = Webhooks.rotate_secret(webhook, user)
          send(self(), {:secrets, webhook, [secret, rotated]})
        end)

      assert_received {:secrets, webhook, secrets}
      stored = Repo.get!(Webhook, webhook.id)

      events = Activity.list(%{schema: Webhook, entry_id: webhook.id})
      assert Enum.map(events, & &1.action) |> Enum.sort() == [:created, :updated]

      for secret <- secrets do
        refute inspect(stored) =~ secret
        refute log =~ secret
        refute inspect(events) =~ secret
      end

      refute inspect(stored) =~ stored.secret_ciphertext
      refute inspect(stored) =~ "secret_ciphertext"
    end

    test "rotating invalidates the old secret at once", %{user: user} do
      receiver = WebhookReceiver.start()
      {webhook, old} = create_webhook(user, WebhookReceiver.url(receiver))
      {:ok, webhook, new} = Webhooks.rotate_secret(webhook, user)
      assert new != old
      assert webhook.secret_rotated_at

      {:ok, _} = Webhooks.send_test(webhook, user)
      request = next_request()
      signature = request.headers["brando-signature"]

      assert Signature.verify(signature, request.body, new) == :ok
      assert Signature.verify(signature, request.body, old) == {:error, :signature_mismatch}
    end
  end

  describe "deliveries" do
    test "a content change is posted, signed over the exact body, with no content", %{user: user} do
      receiver = WebhookReceiver.start()
      {webhook, secret} = create_webhook(user, WebhookReceiver.url(receiver))

      page = create_page(user)
      request = next_request()

      assert request.method == "POST"
      assert request.path == "/hook"
      assert request.headers["content-type"] == "application/json"
      assert request.headers["brando-event"] == "entry.created"
      assert Signature.verify(request.headers["brando-signature"], request.body, secret) == :ok

      payload = Jason.decode!(request.body)
      assert payload["event"] == "entry.created"
      assert payload["delivery_id"] == request.headers["brando-delivery"]
      assert {:ok, _} = Ecto.UUID.cast(payload["event_id"])
      assert payload["entry"]["type"] == "pages.page"
      assert payload["entry"]["id"] == page.id
      assert payload["entry"]["language"] == "en"
      assert payload["entry"]["status"] == "draft"
      assert payload["entry"]["url"] =~ page.uri
      assert "title" in payload["entry"]["changed_fields"]
      assert payload["actor"] == %{"kind" => "person"}
      assert Map.has_key?(payload, "site")
      assert Map.has_key?(payload, "environment")

      # No entry content, no user details
      refute request.body =~ "Top secret launch"
      refute request.body =~ user.email
      refute request.body =~ user.name

      assert [delivery] = deliveries(webhook)
      assert delivery.state == "succeeded"
      assert delivery.response_status == 200
      assert delivery.response_body == "ok"
      assert delivery.attempts == 1
      assert is_integer(delivery.duration_ms)
      assert delivery.entry_id == page.id

      assert %{last_delivery_state: "succeeded"} = Repo.get!(Webhook, webhook.id)
    end

    test "events, content types and languages filter what a webhook gets", %{user: user} do
      receiver = WebhookReceiver.start()

      {only_published, _} =
        create_webhook(user, WebhookReceiver.url(receiver, "/published"), %{"events" => ["entry.published"]})

      {other_type, _} =
        create_webhook(user, WebhookReceiver.url(receiver, "/fragments"), %{"entry_types" => ["pages.fragment"]})

      {norwegian, _} = create_webhook(user, WebhookReceiver.url(receiver, "/no"), %{"languages" => ["no"]})

      page = create_page(user)
      refute_receive {:webhook_request, _}, 200

      {:ok, _} = Pages.update_page(page.id, %{status: :published}, user)
      assert next_request().path == "/published"
      refute_receive {:webhook_request, _}, 200

      assert [%{event: "entry.published"}] = deliveries(only_published)
      assert deliveries(other_type) == []
      assert deliveries(norwegian) == []
    end

    test "a failed attempt is retried with backoff; the last one pauses the webhook", %{user: user} do
      receiver = WebhookReceiver.start(fn _ -> {500, "broken"} end)
      {webhook, _} = create_webhook(user, WebhookReceiver.url(receiver))

      Oban.Testing.with_testing_mode(:manual, fn ->
        create_page(user)
        [event_job] = all_enqueued(worker: ContentEventDispatcher)
        assert :ok = perform_job(ContentEventDispatcher, event_job.args)

        [job] = all_enqueued(worker: WebhookDelivery)
        assert job.queue == "webhooks"
        assert job.max_attempts == 15

        assert {:error, "HTTP 500"} = perform_job(WebhookDelivery, job.args)
        assert [%{state: "retrying", response_status: 500, attempts: 1}] = deliveries(webhook)
        assert %{active: true, failing_since: %DateTime{}} = Repo.get!(Webhook, webhook.id)

        ExUnit.CaptureLog.capture_log(fn ->
          assert {:cancel, "HTTP 500"} = perform_job(WebhookDelivery, job.args, attempt: 15)
        end)

        assert [%{state: "failed", attempts: 2}] = deliveries(webhook)
        assert %{active: false, paused_reason: :failures} = Repo.get!(Webhook, webhook.id)
        assert [%{id: id}] = Webhooks.paused_after_failures()
        assert id == webhook.id
      end)
    end

    test "backoff doubles from 30 seconds to four hours, over about a day" do
      waits = Enum.map(1..14, &WebhookDelivery.backoff(%Oban.Job{attempt: &1}))

      assert Enum.at(waits, 0) in 30..33
      assert Enum.at(waits, 1) in 60..66
      assert Enum.at(waits, 2) in 120..132
      assert Enum.at(waits, 13) in 14_400..15_840
      total = Enum.sum(waits)
      assert total > 22 * 3600 and total < 27 * 3600
    end

    test "the timeout is enforced", %{user: user} do
      put_test_env(Brando.Webhooks, allow_localhost: true, resolver: @resolver, timeout: 300)
      receiver = WebhookReceiver.start(fn _ -> {:sleep, 2_000} end)
      {webhook, _} = create_webhook(user, WebhookReceiver.url(receiver))

      {:ok, _} = Webhooks.send_test(webhook, user)
      assert [delivery] = deliveries(webhook)
      assert delivery.state == "failed"
      assert delivery.error == "timeout"
      assert delivery.duration_ms < 1_500
    end

    test "redirects are not followed", %{user: user} do
      receiver =
        WebhookReceiver.start(fn
          %{path: "/hook"} -> {302, [{"location", "http://127.0.0.1/elsewhere"}], ""}
          _ -> {200, "followed"}
        end)

      {webhook, _} = create_webhook(user, WebhookReceiver.url(receiver))
      {:ok, _} = Webhooks.send_test(webhook, user)

      assert next_request().path == "/hook"
      refute_receive {:webhook_request, _}, 200
      assert [%{state: "failed", response_status: 302}] = deliveries(webhook)
    end

    test "only the first 4 KB of a response are read and kept", %{user: user} do
      receiver = WebhookReceiver.start(fn _ -> {200, String.duplicate("a", 50_000)} end)
      {webhook, _} = create_webhook(user, WebhookReceiver.url(receiver))
      {:ok, _} = Webhooks.send_test(webhook, user)

      assert [%{state: "succeeded", response_body: body}] = deliveries(webhook)
      assert byte_size(body) == 4096
    end

    test "a slow receiver gets no more than the concurrency limit at once", %{user: user} do
      receiver = WebhookReceiver.start()
      {webhook, _} = create_webhook(user, WebhookReceiver.url(receiver))

      Oban.Testing.with_testing_mode(:manual, fn ->
        for _ <- 1..3, do: {:ok, _} = Webhooks.send_test(webhook, user)
        [first, second, third] = all_enqueued(worker: WebhookDelivery)

        # Two still sending
        for job <- [first, second] do
          Repo.update_all(from(d in Delivery, where: d.id == ^job.args["delivery"]),
            set: [state: "sending", started_at: DateTime.utc_now()]
          )
        end

        assert {:snooze, 5} = perform_job(WebhookDelivery, third.args)
        refute_receive {:webhook_request, _}, 100

        # One of them never finished: it stops counting after the timeout
        Repo.update_all(from(d in Delivery, where: d.id == ^first.args["delivery"]),
          set: [started_at: DateTime.add(DateTime.utc_now(), -60, :second)]
        )

        assert :ok = perform_job(WebhookDelivery, third.args)
        assert next_request()
      end)
    end

    test "connects to the address it checked, keeping the host name", %{user: user} do
      receiver = WebhookReceiver.start()
      {webhook, _} = create_webhook(user, "http://pinned.test:#{receiver.port}/hook")
      {:ok, _} = Webhooks.send_test(webhook, user)
      assert next_request().headers["host"] == "pinned.test:#{receiver.port}"
    end

    test "a host that moved to a private address is refused at delivery (DNS rebinding)", %{user: user} do
      receiver = WebhookReceiver.start()
      Brando.WebhookTestResolver.rebind({93, 184, 216, 34})
      {webhook, _} = create_webhook(user, "http://rebind.test:#{receiver.port}/hook")

      Brando.WebhookTestResolver.rebind({10, 0, 0, 5})

      ExUnit.CaptureLog.capture_log(fn -> create_page(user) end)

      refute_receive {:webhook_request, _}, 200
      assert [%{state: "failed", error: "private_address"}] = deliveries(webhook)
      assert %{active: false, paused_reason: :failures} = Repo.get!(Webhook, webhook.id)
    after
      Brando.WebhookTestResolver.rebind({93, 184, 216, 34})
    end

    test "the test event goes through the same checks", %{user: user} do
      receiver = WebhookReceiver.start()
      Brando.WebhookTestResolver.rebind({93, 184, 216, 34})
      {webhook, _} = create_webhook(user, "http://rebind.test:#{receiver.port}/hook")
      Brando.WebhookTestResolver.rebind({169, 254, 169, 254})

      {:ok, _} = Webhooks.send_test(webhook, user)
      refute_receive {:webhook_request, _}, 200
      assert [%{test: true, state: "failed", error: "private_address"}] = deliveries(webhook)
      # A test event does not pause the webhook
      assert %{active: true} = Repo.get!(Webhook, webhook.id)
    after
      Brando.WebhookTestResolver.rebind({93, 184, 216, 34})
    end

    test "a test event", %{user: user} do
      receiver = WebhookReceiver.start()
      {webhook, _} = create_webhook(user, WebhookReceiver.url(receiver))
      {:ok, _} = Webhooks.send_test(webhook, user)

      payload = Jason.decode!(next_request().body)
      assert payload["event"] == "webhook.test"
      assert payload["entry"] == nil
      assert [%{state: "succeeded", test: true}] = deliveries(webhook)
    end

    test "redelivery sends the same event with a new delivery id", %{user: user} do
      receiver = WebhookReceiver.start()
      {webhook, _} = create_webhook(user, WebhookReceiver.url(receiver))
      create_page(user)
      first = Jason.decode!(next_request().body)

      [original] = deliveries(webhook)
      {:ok, redelivery} = Webhooks.redeliver(original, user)
      again = Jason.decode!(next_request().body)

      assert again["event_id"] == first["event_id"]
      assert again["delivery_id"] != first["delivery_id"]
      assert again["delivery_id"] == redelivery.delivery_id
      assert redelivery.redelivery_of_id == original.id
    end

    test "a paused webhook gets nothing, and its queued deliveries are not sent", %{user: user} do
      receiver = WebhookReceiver.start()
      {webhook, _} = create_webhook(user, WebhookReceiver.url(receiver))

      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, _} = Webhooks.send_test(webhook, user)
        [job] = all_enqueued(worker: WebhookDelivery)
        {:ok, paused} = Webhooks.pause(webhook, user)

        assert {:cancel, :webhook_paused} = perform_job(WebhookDelivery, job.args)
        assert [%{state: "cancelled"}] = deliveries(webhook)
        assert {:error, :paused} = Webhooks.send_test(paused, user)
      end)

      create_page(user)
      refute_receive {:webhook_request, _}, 200
    end

    test "the dispatcher running twice queues each delivery once", %{user: user} do
      receiver = WebhookReceiver.start()
      {webhook, _} = create_webhook(user, WebhookReceiver.url(receiver))

      Oban.Testing.with_testing_mode(:manual, fn ->
        create_page(user)
        [event_job] = all_enqueued(worker: ContentEventDispatcher)
        assert :ok = perform_job(ContentEventDispatcher, event_job.args)
        assert :ok = perform_job(ContentEventDispatcher, event_job.args)
        assert [_] = deliveries(webhook)
      end)
    end
  end

  describe "saving" do
    test "refuses http without the override, credentials and private addresses", %{user: user} do
      put_test_env(Brando.Webhooks, resolver: @resolver)

      for {url, reason} <- [
            {"http://hooks.example.com/", :https_required},
            {"https://user:pw@hooks.example.com/", :credentials_in_url},
            {"https://db.internal.test/", :private_address},
            {"https://127.0.0.1/", :private_address},
            {"https://nowhere.test/", :unresolvable}
          ] do
        assert {:error, changeset} = Webhooks.create_webhook(%{"name" => "x", "url" => url}, user)
        assert [{_, opts}] = Keyword.get_values(changeset.errors, :url)
        assert opts[:reason] == reason
      end

      assert {:ok, _webhook, _secret} =
               Webhooks.create_webhook(%{"name" => "x", "url" => "https://hooks.example.com/"}, user)
    end

    test "only known events, content types and languages", %{user: user} do
      assert {:error, changeset} =
               Webhooks.create_webhook(
                 %{"name" => "x", "url" => "https://hooks.example.com/", "events" => ["entry.exploded"]},
                 user
               )

      assert Keyword.has_key?(changeset.errors, :events)
    end

    test "changes are written to Activity, without the URL's path", %{user: user} do
      {:ok, webhook, _} =
        Webhooks.create_webhook(%{"name" => "Slack", "url" => "https://hooks.example.com/services/T0/B0/token"}, user)

      {:ok, webhook} = Webhooks.update_webhook(webhook, %{"events" => ["entry.published"]}, user)
      {:ok, _} = Webhooks.delete_webhook(webhook, user)

      events = Activity.list(%{schema: Webhook, entry_id: webhook.id})
      assert Enum.map(events, & &1.action) |> Enum.sort() == [:created, :deleted, :updated]
      assert Enum.all?(events, &(&1.title == "Slack"))
      assert Enum.find(events, &(&1.action == :updated)).fields == ["events"]
      refute inspect(events) =~ "token"
    end
  end

  describe "authorization" do
    test "without groups, admins and superusers manage webhooks, editors don't" do
      put_test_env(:authorization_mode, :legacy)
      editor = Factory.insert(:random_user, role: :editor)
      admin = Factory.insert(:random_user, role: :admin)

      refute Webhooks.can_manage?(editor)
      assert Webhooks.can_manage?(admin)

      assert {:error, :forbidden} =
               Webhooks.create_webhook(%{"name" => "x", "url" => "https://hooks.example.com/"}, editor)

      {:ok, webhook, _} = Webhooks.create_webhook(%{"name" => "x", "url" => "https://hooks.example.com/"}, admin)

      assert {:error, :forbidden} = Webhooks.update_webhook(webhook, %{"name" => "y"}, editor)
      assert {:error, :forbidden} = Webhooks.rotate_secret(webhook, editor)
      assert {:error, :forbidden} = Webhooks.delete_webhook(webhook, editor)
      assert {:error, :forbidden} = Webhooks.send_test(webhook, editor)
      assert {:error, :forbidden} = Webhooks.pause(webhook, editor)
    end

    test "with groups, the Webhooks permission decides" do
      alias Brando.Authorization.{Catalog, Groups, Migration, Scope}

      owner = Factory.insert(:random_user, role: :superuser)
      put_test_env(:authorization_mode, :groups)
      {:ok, _} = Migration.run()
      with_permission = Factory.insert(:random_user, role: :user)
      without = Factory.insert(:random_user, role: :admin)

      {:ok, group} =
        Groups.create(Scope.standalone(owner), %{name: "Integrations"}, [
          Catalog.get(:access, :backend).key,
          Catalog.get(:manage, :webhooks).key
        ])

      {:ok, :ok} = Groups.add_member(Scope.standalone(owner), group.id, with_permission.id)

      assert Catalog.get(:manage, :webhooks).key == "brando.webhooks.manage"
      assert Webhooks.can_manage?(with_permission)
      refute Webhooks.can_manage?(without)

      assert {:error, :forbidden} =
               Webhooks.create_webhook(%{"name" => "x", "url" => "https://hooks.example.com/"}, without)

      assert {:ok, _, _} =
               Webhooks.create_webhook(%{"name" => "x", "url" => "https://hooks.example.com/"}, with_permission)
    end
  end

  describe "tenancy" do
    setup do
      put_test_env(:tenancy_mode, :multi)

      for prefix <- ["tenant_hooks-a_production", "tenant_hooks-b_production"] do
        create_tenant_tables(prefix)
      end

      :ok
    end

    defp create_tenant_tables(prefix) do
      Repo.query!(~s|CREATE SCHEMA "#{prefix}"|)
      Repo.query!(~s|CREATE TABLE "#{prefix}".webhooks (LIKE public.webhooks INCLUDING ALL)|)
      Repo.query!(~s|CREATE TABLE "#{prefix}".webhook_deliveries (LIKE public.webhook_deliveries INCLUDING ALL)|)
    end

    test "a webhook belongs to its site environment; ids from another are not found", %{user: user} do
      {:ok, webhook, _} =
        Brando.Tenant.with_prefix("tenant_hooks-a_production", fn ->
          Webhooks.create_webhook(%{"name" => "A", "url" => "https://hooks.example.com/"}, user)
        end)

      Brando.Tenant.with_prefix("tenant_hooks-b_production", fn ->
        assert Webhooks.list_webhooks() == []
        assert {:error, :not_found} = Webhooks.get_webhook(webhook.id)
        assert {:error, :not_found} = Webhooks.get_webhook(to_string(webhook.id))
      end)

      Brando.Tenant.with_prefix("tenant_hooks-a_production", fn ->
        assert {:ok, %Webhook{name: "A"}} = Webhooks.get_webhook(webhook.id)
      end)
    end

    test "copying an environment pauses the copy's webhooks and clears its log", %{user: user} do
      prefix = "tenant_hooks-b_production"

      {:ok, webhook, _} =
        Brando.Tenant.with_prefix(prefix, fn ->
          {:ok, webhook, secret} =
            Webhooks.create_webhook(%{"name" => "Prod cache", "url" => "https://hooks.example.com/"}, user)

          Repo.insert!(
            %Delivery{
              webhook_id: webhook.id,
              delivery_id: Ecto.UUID.generate(),
              event: "entry.updated",
              payload: %{},
              state: "succeeded"
            },
            prefix: prefix
          )

          {:ok, webhook, secret}
        end)

      assert :ok = Webhooks.after_environment_copy(prefix)

      Brando.Tenant.with_prefix(prefix, fn ->
        assert {:ok, %Webhook{active: false, paused_reason: :environment_copy}} = Webhooks.get_webhook(webhook.id)
        assert Webhooks.list_all_deliveries() == []
      end)
    end
  end

  describe "the environment lifecycle" do
    defmodule CopyingCloner do
      @behaviour Brando.Environments.SchemaCloner

      # Stands in for pg_dump: the tables webhooks use, with their rows.
      @impl true
      def clone_schema(source, target) do
        :ok = Brando.Environments.Schema.create(target)

        for table <- ["webhooks", "webhook_deliveries", "activity_events"] do
          Brando.Repo.repo().query!(~s|CREATE TABLE "#{target}".#{table} (LIKE "#{source}".#{table} INCLUDING ALL)|)
          Brando.Repo.repo().query!(~s|INSERT INTO "#{target}".#{table} SELECT * FROM "#{source}".#{table}|)
        end

        :ok
      end
    end

    defmodule NoMigrator do
      @behaviour Brando.Environments.Migrator
      @impl true
      def migrate(_site, _environment), do: {:ok, []}
    end

    setup %{user: user} do
      alias Brando.Tenant.Registry

      put_test_env(:tenancy_mode, :multi)
      put_test_env(:environment_schema_cloner, CopyingCloner)
      put_test_env(:tenant_migrator, NoMigrator)
      put_test_env(:sites_path, Path.join(System.tmp_dir!(), "brando-webhooks-#{System.unique_integer([:positive])}"))
      Brando.Tenant.Cache.clear()
      on_exit(fn -> Brando.Tenant.Cache.clear() end)

      {:ok, site} =
        Registry.create_site(%{
          name: "Hooks",
          key: "hooks-copy",
          languages: ["en"],
          default_language: "en",
          status: :active,
          delivery_mode: :dynamic
        })

      {:ok, production} = Registry.create_environment(site, %{name: "Production", key: "production", live: true})
      {:ok, staging} = Registry.create_environment(site, %{name: "Staging", key: "staging", live: false})

      for prefix <- ["tenant_hooks-copy_production", "tenant_hooks-copy_staging"] do
        Repo.query!(~s|CREATE SCHEMA "#{prefix}"|)

        for table <- ["webhooks", "webhook_deliveries", "activity_events"],
            do: Repo.query!(~s|CREATE TABLE "#{prefix}".#{table} (LIKE public.#{table} INCLUDING ALL)|)
      end

      in_production = fn fun -> Brando.Tenant.with_prefix("tenant_hooks-copy_production", fun) end

      {:ok, deploy, _} =
        in_production.(fn ->
          Webhooks.create_webhook(%{"name" => "Deploy hook", "url" => "https://hooks.example.com/deploy"}, user)
        end)

      {:ok, broken, _} =
        in_production.(fn ->
          {:ok, webhook, secret} =
            Webhooks.create_webhook(%{"name" => "Broken cache", "url" => "https://hooks.example.com/cache"}, user)

          {:ok, webhook} = Webhooks.pause(webhook, :failures, :system)

          Brando.Repo.insert!(%Delivery{
            webhook_id: webhook.id,
            delivery_id: Ecto.UUID.generate(),
            event: "entry.updated",
            payload: %{},
            state: "failed"
          })

          {:ok, webhook, secret}
        end)

      %{site: site, production: production, staging: staging, deploy: deploy, broken: broken}
    end

    # The details of a webhook's Activity events in the current environment
    defp webhook_activity(id) do
      Brando.Repo.all(
        from(e in Brando.Activity.Event,
          where: e.schema == ^to_string(Webhook) and e.entry_id == ^id,
          select: e.details
        )
      )
    end

    defp webhook_in(prefix, id) do
      Brando.Tenant.with_prefix(prefix, fn ->
        {:ok, webhook} = Webhooks.get_webhook(id)
        webhook
      end)
    end

    test "a copy's webhooks are paused and its log is empty; the source's are untouched", c do
      assert {:ok, _} = Brando.Environments.copy_environment(c.production, c.staging)

      assert %{active: false, paused_reason: :environment_copy} = webhook_in("tenant_hooks-copy_staging", c.deploy.id)
      # Paused for another reason: left as it was
      assert %{active: false, paused_reason: :failures} = webhook_in("tenant_hooks-copy_staging", c.broken.id)

      Brando.Tenant.with_prefix("tenant_hooks-copy_staging", fn ->
        assert Webhooks.list_all_deliveries() == []

        assert %{"webhook" => "paused", "reason" => "environment_copy"} in webhook_activity(c.deploy.id)
        refute %{"webhook" => "paused", "reason" => "environment_copy"} in webhook_activity(c.broken.id)
      end)

      assert %{active: true} = webhook_in("tenant_hooks-copy_production", c.deploy.id)
    end

    test "going live resumes webhooks paused by the copy, not those paused after failures", c do
      assert {:ok, _} = Brando.Environments.copy_environment(c.production, c.staging)
      assert {:ok, %{live: true}} = Brando.Environments.set_live(c.staging)

      assert %{active: true, paused_reason: nil} = webhook_in("tenant_hooks-copy_staging", c.deploy.id)
      assert %{active: false, paused_reason: :failures} = webhook_in("tenant_hooks-copy_staging", c.broken.id)

      Brando.Tenant.with_prefix("tenant_hooks-copy_staging", fn ->
        assert %{"webhook" => "resumed", "reason" => "went_live"} in webhook_activity(c.deploy.id)
        refute %{"webhook" => "resumed", "reason" => "went_live"} in webhook_activity(c.broken.id)
      end)

      # The environment that was live keeps its webhooks as they were
      assert %{active: true} = webhook_in("tenant_hooks-copy_production", c.deploy.id)
      assert %{active: false, paused_reason: :failures} = webhook_in("tenant_hooks-copy_production", c.broken.id)
    end

    test "a webhook paused by hand in the copy stays paused when it goes live", c do
      assert {:ok, _} = Brando.Environments.copy_environment(c.production, c.staging)

      Brando.Tenant.with_prefix("tenant_hooks-copy_staging", fn ->
        {:ok, webhook} = Webhooks.get_webhook(c.deploy.id)
        {:ok, webhook} = Webhooks.resume(webhook, :system)
        {:ok, _} = Webhooks.pause(webhook, :manual, :system)
      end)

      assert {:ok, _} = Brando.Environments.set_live(c.staging)
      assert %{active: false, paused_reason: :manual} = webhook_in("tenant_hooks-copy_staging", c.deploy.id)
    end

    test "an archive restored as a new environment has its webhooks paused", c do
      # Going live archives production, webhooks active
      assert {:ok, _} = Brando.Environments.set_live(c.staging)
      assert {:ok, restored} = Brando.Environments.rollback(c.site)
      refute restored.live

      prefix = Brando.Tenant.prefix(c.site, restored)
      assert %{active: false, paused_reason: :environment_copy} = webhook_in(prefix, c.deploy.id)
      assert %{active: false, paused_reason: :failures} = webhook_in(prefix, c.broken.id)
      Brando.Tenant.with_prefix(prefix, fn -> assert Webhooks.list_all_deliveries() == [] end)

      # Making it live again resumes it
      assert {:ok, _} = Brando.Environments.set_live(restored)
      assert %{active: true} = webhook_in(prefix, c.deploy.id)
    end
  end

  describe "retention" do
    test "deliveries past the retention period are removed by the nightly purge", %{user: user} do
      {:ok, webhook, _} = Webhooks.create_webhook(%{"name" => "x", "url" => "https://hooks.example.com/"}, user)

      insert = fn days_ago ->
        Repo.insert!(%Delivery{
          webhook_id: webhook.id,
          delivery_id: Ecto.UUID.generate(),
          event: "entry.updated",
          payload: %{},
          state: "succeeded",
          inserted_at: DateTime.add(DateTime.utc_now(), -days_ago * 86_400, :second)
        })
      end

      old = insert.(31)
      recent = insert.(29)

      assert Webhooks.retention_days() == 30
      assert :ok = perform_job(Brando.Worker.WebhookDeliveryPurger, %{})

      assert Repo.get(Delivery, recent.id)
      refute Repo.get(Delivery, old.id)

      put_test_env(Brando.Webhooks, retention_days: 7)
      assert Webhooks.purge_deliveries() == 1
    end
  end
end
