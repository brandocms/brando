defmodule Brando.NotificationsTest do
  use ExUnit.Case
  use Brando.ConnCase

  import Ecto.Query, only: [from: 2]
  import Swoosh.TestAssertions

  alias Brando.Activity
  alias Brando.Factory
  alias Brando.Notes
  alias Brando.Notifications.Delivery
  alias Brando.Notifications.Digest
  alias Brando.Notifications.JobFailures
  alias Brando.Notifications.Message
  alias Brando.Notifications.Route
  alias Brando.Notifications.Routing
  alias Brando.Pages
  alias Brando.Pages.Page
  alias Brando.Users.UserConfig
  alias Brando.WebhookReceiver
  alias Brando.Worker.NotificationDelivery

  @resolver {Brando.WebhookTestResolver, :resolve}

  setup do
    # The fake receiver listens on loopback, which only the development
    # override allows.
    put_test_env(Brando.Webhooks, allow_localhost: true, resolver: @resolver)
    put_test_env(Brando.ContentEvents, debounce_seconds: 0)
    user = Factory.insert(:random_user, name: "Ingrid Hauge")
    {:ok, %{user: user}}
  end

  defp route!(user, attrs) do
    {:ok, route} = Routing.create_route(Map.merge(%{"name" => "Editors", "events" => ["scheduled_publish"]}, attrs), user)
    route
  end

  defp slack_route!(user, receiver, attrs \\ %{}) do
    route!(
      user,
      Map.merge(%{"kind" => "slack", "url" => WebhookReceiver.url(receiver, "/services/T0/B0/secretpart")}, attrs)
    )
  end

  defp create_page(user, attrs \\ %{}) do
    {:ok, page} =
      Pages.create_page(
        Map.merge(
          %{
            title: "Spring launch",
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

  defp schedule_status(page, user, status) do
    perform_job(Brando.Worker.EntryPublisher, %{
      "schema" => to_string(Page),
      "id" => page.id,
      "status" => status,
      "user_id" => user.id
    })
  end

  defp next_request do
    assert_receive {:webhook_request, request}, 5_000
    request
  end

  defp deliveries(route), do: Routing.list_deliveries(route)

  describe "routes" do
    test "keep a webhook URL encrypted, bound to the route, and show only its host and end", %{user: user} do
      receiver = WebhookReceiver.start()
      url = WebhookReceiver.url(receiver, "/services/T0/B0/secretpart")

      log =
        ExUnit.CaptureLog.capture_log([level: :debug], fn ->
          send(self(), {:route, route!(user, %{"kind" => "slack", "url" => url})})
        end)

      assert_received {:route, route}
      stored = Repo.get!(Route, route.id)

      refute stored.url_ciphertext =~ "secretpart"
      assert stored.url_hint == "127.0.0.1/…part"
      assert Routing.url(stored) == {:ok, url}
      assert {:error, :url_unreadable} = Routing.url(%{stored | id: route.id + 1})

      events = Activity.list(%{schema: Route, entry_id: route.id})

      for text <- [inspect(stored), inspect(route), log, inspect(events)] do
        refute text =~ "secretpart"
      end
    end

    test "keep the saved URL when the form leaves it out, and need a new one for another kind", %{user: user} do
      receiver = WebhookReceiver.start()
      route = slack_route!(user, receiver)

      {:ok, renamed} = Routing.update_route(route, %{"name" => "Desk"}, user)
      assert renamed.url_hint == route.url_hint
      assert {:ok, _} = Routing.url(renamed)

      assert {:error, changeset} = Routing.update_route(renamed, %{"kind" => "teams"}, user)
      assert {_, [validation: :required]} = changeset.errors[:url]

      {:ok, teams} =
        Routing.update_route(renamed, %{"kind" => "teams", "url" => WebhookReceiver.url(receiver, "/workflows/x")}, user)

      assert {:ok, "http://127.0.0.1:" <> _} = Routing.url(teams)
    end

    test "check what they are given", %{user: user} do
      assert {:error, changeset} = Routing.create_route(%{"name" => "Desk", "kind" => "slack", "events" => []}, user)
      assert changeset.errors[:events]
      assert changeset.errors[:url]

      assert {:error, changeset} =
               Routing.create_route(%{"name" => "Desk", "kind" => "email", "events" => ["mention"]}, user)

      assert changeset.errors[:recipient_ids]

      assert {:error, changeset} =
               Routing.create_route(
                 %{
                   "name" => "Desk",
                   "kind" => "slack",
                   "events" => ["mention"],
                   "url" => "https://hooks.internal.test/x"
                 },
                 user
               )

      assert {_, opts} = changeset.errors[:url]
      assert opts[:reason] == :private_address

      assert {:error, changeset} =
               Routing.create_route(
                 %{"name" => "Desk", "kind" => "email", "events" => ["gossip"], "recipient_ids" => [user.id]},
                 user
               )

      assert changeset.errors[:events]
    end

    test "are managed by administrators only", %{user: user} do
      editor = Factory.insert(:random_user, role: :editor)
      attrs = %{"name" => "Desk", "kind" => "email", "events" => ["mention"], "recipient_ids" => [user.id]}

      assert {:error, :forbidden} = Routing.create_route(attrs, editor)
      refute Routing.can_manage?(editor)
      assert Routing.can_manage?(user)

      route = route!(user, Map.delete(attrs, "name"))
      assert {:error, :forbidden} = Routing.delete_route(route, editor)
      assert {:error, :forbidden} = Routing.send_test(route, editor)
    end
  end

  describe "messages" do
    @mention %{
      "event" => "mention",
      "site" => "shop",
      "environment" => "production",
      "author" => "Ingrid",
      "mentioned" => ["Trond", "Ann"],
      "anchor" => "Hero",
      "entry" => %{
        "title" => "Spring <launch> & more",
        "type" => "Page",
        "language" => "en",
        "admin_url" => "https://example.com/admin/pages/update/1"
      }
    }

    test "Slack gets a text fallback and blocks, with Slack's markup escaped" do
      body = Message.slack(@mention)

      assert body["text"] == "Ingrid mentioned Trond, Ann in a note on Spring <launch> & more"

      assert [
               %{"type" => "section", "text" => %{"type" => "mrkdwn", "text" => text}},
               %{"type" => "context", "elements" => [%{"type" => "mrkdwn", "text" => "shop · production"}]}
             ] = body["blocks"]

      assert text =~ "*Ingrid mentioned Trond, Ann in a note on Spring &lt;launch&gt; &amp; more*"
      assert text =~ "On Hero · Page · EN"
      assert text =~ "<https://example.com/admin/pages/update/1|Open in the admin>"
      assert Jason.encode!(body)
    end

    test "Teams gets a message with one Adaptive Card and a button to the entry" do
      body = Message.teams(Map.put(@mention, "event", "scheduled_publish"))

      assert %{
               "type" => "message",
               "attachments" => [
                 %{
                   "contentType" => "application/vnd.microsoft.card.adaptive",
                   "content" => %{"type" => "AdaptiveCard", "version" => "1.4", "body" => blocks, "actions" => actions}
                 }
               ]
             } = body

      assert [
               %{"type" => "TextBlock", "text" => "Published as scheduled: Spring <launch> & more", "weight" => "Bolder"},
               %{"type" => "TextBlock", "text" => "Page · EN"},
               %{"type" => "TextBlock", "text" => "shop · production", "isSubtle" => true}
             ] = blocks

      assert [%{"type" => "Action.OpenUrl", "url" => "https://example.com/admin/pages/update/1"}] = actions
    end

    test "a failed job names the worker and the error, without a link" do
      body =
        Message.teams(%{
          "event" => "failed_job",
          "site" => "shop",
          "job" => %{"worker" => "MyApp.Worker.Sync", "attempt" => 3, "max_attempts" => 3, "error" => "timeout"}
        })

      [%{"content" => card}] = body["attachments"]
      refute Map.has_key?(card, "actions")
      assert [%{"text" => "A background job failed: MyApp.Worker.Sync"}, %{"text" => text} | _] = card["body"]
      assert text =~ "3 of 3"
      assert text =~ "timeout"
    end

    test "are worded in the language asked for" do
      assert %{title: "Publisert som planlagt: Vår" <> _} =
               Message.content(%{"event" => "scheduled_publish", "entry" => %{"title" => "Vår"}}, "no")
    end
  end

  describe "scheduled publishing" do
    test "posts to the Slack routes that send it, with the entry's title and admin link", %{user: user} do
      receiver = WebhookReceiver.start()
      route = slack_route!(user, receiver)
      page = create_page(user)

      assert :ok = schedule_status(page, user, "published")

      request = next_request()
      assert request.path == "/services/T0/B0/secretpart"
      assert request.headers["content-type"] == "application/json"
      body = Jason.decode!(request.body)
      assert body["text"] == "Published as scheduled: Spring launch"
      assert hd(body["blocks"])["text"]["text"] =~ "/admin/pages/update/#{page.id}"

      assert [%Delivery{state: "succeeded", event: "scheduled_publish", entry_id: id, response_status: 200}] =
               deliveries(route)

      assert id == page.id
      assert Repo.reload!(route).last_delivery_state == "succeeded"
    end

    test "a manual publish is not a scheduled one", %{user: user} do
      receiver = WebhookReceiver.start()
      route = slack_route!(user, receiver)
      page = create_page(user)

      {:ok, _} = Pages.update_page(page.id, %{status: :published}, user)
      refute_receive {:webhook_request, _}, 200
      assert deliveries(route) == []
    end

    test "scheduled unpublishing goes to the routes that send it", %{user: user} do
      receiver = WebhookReceiver.start()
      publish = slack_route!(user, receiver)
      unpublish = slack_route!(user, receiver, %{"name" => "Expiry", "events" => ["scheduled_unpublish"]})
      page = create_page(user, %{status: :published})

      assert :ok = schedule_status(page, user, "draft")

      assert Jason.decode!(next_request().body)["text"] == "Unpublished as scheduled: Spring launch"
      assert deliveries(publish) == []
      assert [%{event: "scheduled_unpublish"}] = deliveries(unpublish)
    end

    test "content types limit what a route sends; paused routes send nothing", %{user: user} do
      receiver = WebhookReceiver.start()
      other_type = slack_route!(user, receiver, %{"entry_types" => ["forms.form"]})
      paused = slack_route!(user, receiver, %{"name" => "Paused"})
      {:ok, _} = Routing.pause(paused, user)
      pages = slack_route!(user, receiver, %{"name" => "Pages", "entry_types" => ["pages.page"]})

      page = create_page(user)
      assert :ok = schedule_status(page, user, "published")

      next_request()
      refute_receive {:webhook_request, _}, 200
      assert deliveries(other_type) == []
      assert deliveries(paused) == []
      assert [_] = deliveries(pages)
    end

    test "Teams routes get an Adaptive Card", %{user: user} do
      receiver = WebhookReceiver.start(fn _ -> {202, ""} end)
      route = route!(user, %{"kind" => "teams", "url" => WebhookReceiver.url(receiver, "/workflows/abc")})
      page = create_page(user)

      assert :ok = schedule_status(page, user, "published")

      assert %{"type" => "message", "attachments" => [%{"content" => %{"type" => "AdaptiveCard"}}]} =
               Jason.decode!(next_request().body)

      assert [%{state: "succeeded", response_status: 202}] = deliveries(route)
    end
  end

  describe "mentions" do
    test "go to Slack naming the author and the people, never the note's text", %{user: user} do
      receiver = WebhookReceiver.start()
      route = slack_route!(user, receiver, %{"events" => ["mention"]})
      other = Factory.insert(:random_user, name: "Trond Mjøen")
      page = Factory.insert(:page, creator: user, title: "Spring launch")

      {:ok, _note, _} =
        Notes.create_thread(Page, page.id, user, %{"body" => "@Trond Mjøen the secret plan", "mentions" => [other.id]})

      body = Jason.decode!(next_request().body)
      assert body["text"] == "Ingrid Hauge mentioned Trond Mjøen in a note on Spring launch"
      refute inspect(body) =~ "secret plan"
      assert [%{event: "mention"}] = deliveries(route)
    end

    test "email routes skip the person mentioned, who has their own email", %{user: user} do
      other = Factory.insert(:random_user, name: "Trond Mjøen")
      watcher = Factory.insert(:random_user, name: "Kari")
      route = route!(user, %{"kind" => "email", "events" => ["mention"], "recipient_ids" => [other.id, watcher.id]})
      page = Factory.insert(:page, creator: user, title: "Spring launch")

      {:ok, _note, _} =
        Notes.create_thread(Page, page.id, user, %{"body" => "@Trond Mjøen look", "mentions" => [other.id]})

      assert [%{recipient_id: recipient_id, state: "succeeded"}] = deliveries(route)
      assert recipient_id == watcher.id

      assert_email_sent(fn email -> email.to == [{"", other.email}] and email.subject =~ "mentioned you" end)
      assert_email_sent(fn email -> email.to == [{"", watcher.email}] and email.subject =~ "mentioned Trond Mjøen" end)
    end
  end

  describe "failed jobs" do
    setup do
      put_test_env(Brando.Notifications, failed_jobs: true)
      :ok
    end

    defp discard(worker, opts \\ []) do
      job = %Oban.Job{
        id: 42,
        worker: worker,
        queue: "default",
        attempt: 5,
        max_attempts: 5,
        args: Keyword.get(opts, :args, %{})
      }

      JobFailures.handle_event(
        [:oban, :job, :exception],
        %{},
        %{job: job, state: :discard, error: RuntimeError.exception("upstream timeout\nstack")},
        nil
      )
    end

    test "a discarded job goes to the failed-job routes, with the first line of its error", %{user: user} do
      receiver = WebhookReceiver.start()
      route = slack_route!(user, receiver, %{"events" => ["failed_job"]})

      assert :ok = discard("MyApp.Worker.Sync")

      body = Jason.decode!(next_request().body)
      assert body["text"] == "A background job failed: MyApp.Worker.Sync"
      text = hd(body["blocks"])["text"]["text"]
      assert text =~ "5 of 5"
      assert text =~ "upstream timeout"
      refute text =~ "stack"
      assert [%{event: "failed_job", entry_id: nil}] = deliveries(route)
    end

    test "notification jobs are never notified, and nothing is sent when it is off", %{user: user} do
      receiver = WebhookReceiver.start()
      route = slack_route!(user, receiver, %{"events" => ["failed_job"]})

      assert :ok = discard("Brando.Worker.NotificationDelivery")
      put_test_env(Brando.Notifications, failed_jobs: false)
      assert :ok = discard("MyApp.Worker.Sync")

      refute_receive {:webhook_request, _}, 200
      assert deliveries(route) == []
    end

    test "content-type filters do not hold them back", %{user: user} do
      receiver = WebhookReceiver.start()
      route = slack_route!(user, receiver, %{"events" => ["failed_job"], "entry_types" => ["pages.page"]})

      assert :ok = discard("MyApp.Worker.Sync")
      next_request()
      assert [_] = deliveries(route)
    end

    test "a webhook paused after its deliveries kept failing is one", %{user: user} do
      receiver = WebhookReceiver.start(fn _ -> {500, "down"} end)
      route = slack_route!(user, WebhookReceiver.start(), %{"events" => ["failed_job"]})

      {:ok, webhook, _secret} =
        Brando.Webhooks.create_webhook(%{"name" => "Shop cache", "url" => WebhookReceiver.url(receiver)}, user)

      _page = create_page(user)
      [delivery] = Brando.Webhooks.list_deliveries(webhook)

      job = %Oban.Job{
        args: %{"delivery" => delivery.id, "webhook" => webhook.id},
        attempt: 15,
        max_attempts: 15
      }

      Brando.Worker.WebhookDelivery.deliver(job)

      assert [%{event: "failed_job", notification: %{"webhook" => %{"name" => "Shop cache"}}}] =
               Enum.filter(deliveries(route), &(&1.state == "succeeded"))
    end
  end

  describe "failures" do
    test "a failing channel is retried, and paused when the last attempt fails", %{user: user} do
      receiver = WebhookReceiver.start(fn _ -> {500, "no"} end)
      route = slack_route!(user, receiver)

      Oban.Testing.with_testing_mode(:manual, fn ->
        page = create_page(user)

        Brando.Activity.with_source(:scheduler, fn ->
          {:ok, _} = Pages.update_page(page.id, %{status: :published}, user)
        end)

        Oban.drain_queue(queue: :content_events)
      end)

      [delivery] = deliveries(route)
      args = %{"delivery" => delivery.id, "route" => route.id}

      assert {:error, "HTTP 500"} = NotificationDelivery.deliver(%Oban.Job{args: args, attempt: 1, max_attempts: 10})
      assert %{state: "retrying", response_status: 500, attempts: 1} = Repo.reload!(delivery)
      assert Repo.reload!(route).active

      assert {:cancel, "HTTP 500"} = NotificationDelivery.deliver(%Oban.Job{args: args, attempt: 10, max_attempts: 10})
      assert %{state: "failed"} = Repo.reload!(delivery)
      assert %{active: false, paused_reason: :failures} = Repo.reload!(route)
    end

    test "a test notification is tried once", %{user: user} do
      receiver = WebhookReceiver.start(fn _ -> {404, "no_service"} end)
      route = slack_route!(user, receiver)

      assert {:ok, [_]} = Routing.send_test(route, user)
      assert Jason.decode!(next_request().body)["text"] =~ "Test notification"
      assert [%{state: "failed", test: true, response_body: "no_service"}] = deliveries(route)
      assert Repo.reload!(route).active
    end

    test "a route paused meanwhile cancels what was queued", %{user: user} do
      receiver = WebhookReceiver.start()
      route = slack_route!(user, receiver)

      {:ok, delivery} =
        %Delivery{}
        |> Ecto.Changeset.change(%{route_id: route.id, event: "scheduled_publish", notification: %{"event" => "test"}})
        |> Repo.insert()

      {:ok, _} = Routing.pause(route, user)

      assert {:cancel, :route_paused} =
               NotificationDelivery.deliver(%Oban.Job{
                 args: %{"delivery" => delivery.id, "route" => route.id},
                 attempt: 1,
                 max_attempts: 10
               })

      assert %{state: "cancelled", error: "route_paused"} = Repo.reload!(delivery)
      refute_receive {:webhook_request, _}, 100
    end

    test "email that cannot be read by the recipient is not sent", %{user: user} do
      inactive = Factory.insert(:random_user)
      route = route!(user, %{"kind" => "email", "recipient_ids" => [inactive.id]})
      inactive |> Ecto.Changeset.change(active: false) |> Repo.update!()
      page = create_page(user)

      assert :ok = schedule_status(page, user, "published")

      assert [%{state: "cancelled", error: "recipient_unavailable"}] = deliveries(route)
      assert_no_email_sent()
    end
  end

  describe "email and digests" do
    test "a recipient without a digest gets a single email in their language", %{user: user} do
      norwegian = Factory.insert(:random_user, language: "no")
      route = route!(user, %{"kind" => "email", "recipient_ids" => [norwegian.id]})
      page = create_page(user)

      assert :ok = schedule_status(page, user, "published")

      assert_email_sent(fn email ->
        assert email.to == [{"", norwegian.email}]
        assert email.subject == "Publisert som planlagt: Spring launch"
        assert email.text_body =~ "/admin/pages/update/#{page.id}"
      end)

      assert [%{state: "succeeded"}] = deliveries(route)
    end

    test "a daily digest collects mentions and notifications until it is due", %{user: user} do
      reader = Factory.insert(:random_user, name: "Kari", config: %UserConfig{notification_digest: :daily})
      route = route!(user, %{"kind" => "email", "recipient_ids" => [reader.id]})
      page = create_page(user)

      assert :ok = schedule_status(page, user, "published")

      {:ok, _note, _} =
        Notes.create_thread(Page, page.id, user, %{"body" => "@Kari have a look", "mentions" => [reader.id]})

      # Waiting for the summary: no single email, no mention email
      assert_no_email_sent()
      assert [%{state: "digest"} = waiting] = deliveries(route)

      due = Digest.next_at(:daily, waiting.inserted_at)
      assert {:snooze, seconds} = Notes.deliver_mentions(reader.id, DateTime.add(due, -60, :second))
      assert seconds in 59..60

      assert :ok = Notes.deliver_mentions(reader.id, due)

      assert_email_sent(fn email ->
        assert email.to == [{"", reader.email}]
        assert email.subject == "Your daily summary: 2 notifications"
        assert email.text_body =~ "Published as scheduled: Spring launch"
        assert email.text_body =~ "have a look"
      end)

      assert [%{state: "succeeded"}] = deliveries(route)
      assert :ok = Notes.deliver_mentions(reader.id, DateTime.add(due, 86_400, :second))
      assert_no_email_sent()
    end

    test "turned off, what waited for the digest goes out with the next email", %{user: user} do
      reader = Factory.insert(:random_user, config: %UserConfig{notification_digest: :weekly})
      route = route!(user, %{"kind" => "email", "recipient_ids" => [reader.id]})
      assert :ok = schedule_status(create_page(user), user, "published")
      assert [%{state: "digest"}] = deliveries(route)

      reader
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_embed(:config, %{notification_digest: :off})
      |> Repo.update!()

      assert :ok = Notes.deliver_mentions(reader.id)

      assert_email_sent(fn email -> email.subject == "Your daily summary: 1 notification" end)
      assert [%{state: "succeeded"}] = deliveries(route)
    end

    test "digest times are at the digest hour in the site's time zone, Mondays for weekly" do
      # Wednesday 7 October 2026, 10:00 in Oslo (08:00 UTC)
      wednesday = ~U[2026-10-07 08:00:00Z]

      assert Digest.next_at(:daily, wednesday) == ~U[2026-10-08 06:00:00Z]
      assert Digest.next_at(:daily, ~U[2026-10-08 05:59:00Z]) == ~U[2026-10-08 06:00:00Z]
      assert Digest.next_at(:weekly, wednesday) == ~U[2026-10-12 06:00:00Z]
      # After the clocks go back, 08:00 in Oslo is 07:00 UTC
      assert Digest.next_at(:weekly, ~U[2026-10-26 07:30:00Z]) == ~U[2026-11-02 07:00:00Z]
    end
  end

  describe "environments" do
    setup do
      put_test_env(:tenancy_mode, :multi)
      prefix = "tenant_notify-a_staging"
      Repo.query!(~s|CREATE SCHEMA "#{prefix}"|)

      for table <- ~w(notification_routes notification_deliveries) do
        Repo.query!(~s|CREATE TABLE "#{prefix}".#{table} (LIKE public.#{table} INCLUDING ALL)|)
      end

      {:ok, prefix: prefix}
    end

    test "a copy's routes are paused, its log cleared, and resumed when it goes live", %{user: user, prefix: prefix} do
      {route, manual} =
        Brando.Tenant.with_prefix(prefix, fn ->
          route = route!(user, %{"kind" => "email", "recipient_ids" => [user.id]})
          manual = route!(user, %{"name" => "Off", "kind" => "email", "recipient_ids" => [user.id]})
          {:ok, _} = Routing.pause(manual, user)

          Repo.insert!(%Delivery{route_id: route.id, event: "test", notification: %{}, state: "succeeded"},
            prefix: prefix
          )

          {route, manual}
        end)

      assert :ok = Routing.after_environment_copy(prefix)

      Brando.Tenant.with_prefix(prefix, fn ->
        assert {:ok, %Route{active: false, paused_reason: :environment_copy}} = Routing.get_route(route.id)
        assert {:ok, %Route{paused_reason: :manual}} = Routing.get_route(manual.id)
        assert Routing.list_all_deliveries() == []
      end)

      assert Routing.after_going_live(prefix) == 1

      Brando.Tenant.with_prefix(prefix, fn ->
        assert {:ok, %Route{active: true}} = Routing.get_route(route.id)
        assert {:ok, %Route{active: false, paused_reason: :manual}} = Routing.get_route(manual.id)
      end)
    end

    test "an environment without the tables is left alone" do
      assert :ok = Routing.after_environment_copy("tenant_none_staging")
      assert Routing.after_going_live("tenant_none_staging") == 0
    end
  end

  test "old deliveries are purged, those waiting for a digest kept", %{user: user} do
    receiver = WebhookReceiver.start()
    route = slack_route!(user, receiver)
    old = DateTime.add(DateTime.utc_now(), -40 * 86_400, :second)

    for state <- ["succeeded", "digest"] do
      %Delivery{}
      |> Ecto.Changeset.change(%{route_id: route.id, event: "test", notification: %{}, state: state, inserted_at: old})
      |> Repo.insert!()
    end

    assert Routing.purge_deliveries() == 1
    assert [%{state: "digest"}] = Repo.all(from(d in Delivery, where: d.route_id == ^route.id))
  end
end
