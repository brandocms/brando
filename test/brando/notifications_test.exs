defmodule Brando.NotificationsTest do
  use ExUnit.Case
  use Brando.ConnCase

  import Ecto.Query, only: [from: 2]
  import ExUnit.CaptureLog
  import Swoosh.TestAssertions

  require Phoenix.LiveViewTest

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

  # Runs the publisher's job for the entry once its time has come: it
  # publishes only a pending entry whose publish_at has passed, and
  # deactivates one whose unpublish_at has
  defp schedule_status(page, user, status) do
    passed = DateTime.utc_now() |> DateTime.add(-60) |> DateTime.truncate(:second)

    set =
      if status == "published",
        do: [status: :pending, publish_at: passed],
        else: [unpublish_at: passed]

    {1, _} = Brando.Repo.update_all(from(p in Page, where: p.id == ^page.id), set: set)

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

      assert body["text"] == "Ingrid mentioned Trond, Ann in a note on Spring &lt;launch&gt; &amp; more"

      assert [
               %{"type" => "section", "text" => %{"type" => "mrkdwn", "text" => text}},
               %{"type" => "context", "elements" => [%{"type" => "mrkdwn", "text" => "shop · production"}]}
             ] = body["blocks"]

      assert text =~ "*Ingrid mentioned Trond, Ann in a note on Spring &lt;launch&gt; &amp; more*"
      assert text =~ "Page · EN"
      refute text =~ "Hero"
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

      # Plain text runs: no Markdown is read from a title or a name
      assert [
               %{
                 "type" => "RichTextBlock",
                 "inlines" => [
                   %{
                     "type" => "TextRun",
                     "text" => "Published as scheduled: Spring <launch> & more",
                     "weight" => "Bolder"
                   }
                 ]
               },
               %{"type" => "RichTextBlock", "inlines" => [%{"type" => "TextRun", "text" => "Page · EN"}]},
               %{
                 "type" => "RichTextBlock",
                 "inlines" => [%{"type" => "TextRun", "text" => "shop · production", "isSubtle" => true}]
               }
             ] = blocks

      refute Enum.any?(blocks, &(&1["type"] == "TextBlock"))

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

      assert [
               %{"inlines" => [%{"text" => "A background job failed: MyApp.Worker.Sync"}]},
               %{"inlines" => [%{"text" => text}]} | _
             ] = card["body"]

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

      assert :ok = schedule_status(page, user, "disabled")

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

    test "a failed or cancelled delivery can be sent again, as a new delivery", %{user: user} do
      receiver = WebhookReceiver.start(fn _ -> {500, "no"} end)
      route = slack_route!(user, receiver)
      page = create_page(user)

      assert :ok = schedule_status(page, user, "published")
      next_request()
      [delivery] = deliveries(route)
      args = %{"delivery" => delivery.id, "route" => route.id}
      assert {:cancel, _} = NotificationDelivery.deliver(%Oban.Job{args: args, attempt: 10, max_attempts: 10})
      failed = Repo.reload!(delivery)
      assert Routing.redeliverable?(failed)
      assert Routing.paused_after_failures() |> Enum.map(& &1.id) == [route.id]

      # Paused after the failure: resume first
      assert {:error, :paused} = Routing.redeliver(failed, user)
      {:ok, _} = Routing.resume(Repo.reload!(route), user)
      assert {:error, :forbidden} = Routing.redeliver(failed, Factory.insert(:random_user, role: :editor))

      assert {:ok, again} = Routing.redeliver(failed, user)
      body = Jason.decode!(next_request().body)
      assert body["text"] == "Published as scheduled: Spring launch"
      assert again.id != delivery.id
      assert again.event == "scheduled_publish"
      assert %{state: "failed"} = Repo.reload!(delivery)
      assert length(deliveries(route)) == 2
      assert Routing.paused_after_failures() == []
    end

    test "a delivery that arrived or is on its way is not sent again", %{user: user} do
      receiver = WebhookReceiver.start()
      route = slack_route!(user, receiver)
      {:ok, [delivery]} = Routing.send_test(route, user)
      next_request()

      refute Routing.redeliverable?(Repo.reload!(delivery))
      assert {:error, :not_redeliverable} = Routing.redeliver(Repo.reload!(delivery), user)
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

    test "an email whose recipient check fails on the database is retried, then marked failed", %{user: user} do
      put_test_env(:authorization_mode, :groups)
      put_test_env(:tenancy_mode, :none)
      reader = Factory.insert(:random_user, role: :superuser)
      {:ok, _} = Brando.Authorization.Migration.run()
      route = route!(user, %{"kind" => "email", "recipient_ids" => [reader.id]})
      page = Factory.insert(:page, creator: reader)

      # About an entry read through a schema whose policy the test can make fail
      {:ok, delivery} =
        %Delivery{}
        |> Ecto.Changeset.change(%{
          route_id: route.id,
          recipient_id: reader.id,
          event: "scheduled_publish",
          entry_schema: to_string(Brando.AuthorizationTestResources.Page),
          entry_id: page.id,
          notification: %{"event" => "test"}
        })
        |> Repo.insert()

      Process.put(:authorization_test_policy_raises, %DBConnection.ConnectionError{message: "timeout"})
      job = %Oban.Job{args: %{"delivery" => delivery.id, "route" => route.id}, attempt: 1, max_attempts: 10}

      assert {:error, _} = NotificationDelivery.deliver(job)
      assert %{state: "retrying", error: "recipient_check_failed"} = Repo.reload!(delivery)

      assert {:cancel, _} = NotificationDelivery.deliver(%{job | attempt: 10})
      assert %{state: "failed", error: "recipient_check_failed"} = Repo.reload!(delivery)

      # Any other failure: there is no point in trying again
      other =
        Repo.insert!(%Delivery{
          route_id: route.id,
          recipient_id: reader.id,
          event: "scheduled_publish",
          entry_schema: delivery.entry_schema,
          entry_id: page.id,
          notification: %{"event" => "test"}
        })

      Process.put(:authorization_test_policy_raises, %RuntimeError{message: "association not loaded"})

      capture_log(fn ->
        assert {:cancel, :recipient_check_failed} =
                 NotificationDelivery.deliver(%{job | args: %{"delivery" => other.id, "route" => route.id}})
      end)

      assert %{state: "failed", error: "recipient_check_failed"} = Repo.reload!(other)
      assert_no_email_sent()
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

      # One notification: a single email
      assert_email_sent(fn email -> email.subject == "Published as scheduled: Spring launch" end)
      assert [%{state: "succeeded"}] = deliveries(route)
    end

    test "a mention goes in the digest only while the user may still read the entry", %{user: user} do
      put_test_env(:authorization_mode, :groups)
      put_test_env(:tenancy_mode, :none)
      owner = Factory.insert(:random_user, role: :superuser)

      reader =
        Factory.insert(:random_user, role: :user, name: "Kari", config: %UserConfig{notification_digest: :daily})

      {:ok, _} = Brando.Authorization.Migration.run()
      scope = Brando.Authorization.Scope.standalone(owner)
      {:ok, backend} = Brando.Authorization.Groups.create(scope, %{name: "Backend"}, ["brando.admin.access"])
      {:ok, readers} = Brando.Authorization.Groups.create(scope, %{name: "Readers"}, ["brando.pages.read"])
      {:ok, :ok} = Brando.Authorization.Groups.add_member(scope, backend.id, reader.id)
      {:ok, :ok} = Brando.Authorization.Groups.add_member(scope, readers.id, reader.id)
      page = Factory.insert(:page, creator: user)

      {:ok, _note, _} =
        Notes.create_thread(Page, page.id, owner, %{"body" => "@Kari still readable", "mentions" => [reader.id]})

      [mention] = Notes.mentions_for(reader.id, unsent: true)
      due = Digest.next_at(:daily, mention.inserted_at)
      assert :ok = Notes.deliver_mentions(reader.id, due)
      assert_email_sent(fn email -> assert email.text_body =~ "still readable" end)

      # Read access removed before the next digest: the mention is dropped, not kept for later
      {:ok, _note, _} =
        Notes.create_thread(Page, page.id, owner, %{"body" => "@Kari confidential", "mentions" => [reader.id]})

      {:ok, :ok} = Brando.Authorization.Groups.remove_member(scope, readers.id, reader.id)
      refute Brando.Authorization.can?(reader, :read, page)

      [mention] = Notes.mentions_for(reader.id, unsent: true)
      assert :ok = Notes.deliver_mentions(reader.id, Digest.next_at(:daily, mention.inserted_at))
      assert_no_email_sent()
      assert Notes.mentions_for(reader.id, unsent: true) == []
    end

    test "a digest larger than one batch queues the rest at once", %{user: user} do
      reader = Factory.insert(:random_user, config: %UserConfig{notification_digest: :daily})
      route = route!(user, %{"kind" => "email", "events" => ["failed_job"], "recipient_ids" => [reader.id]})
      now = DateTime.utc_now()

      rows =
        for n <- 1..201 do
          %{
            route_id: route.id,
            recipient_id: reader.id,
            event: "failed_job",
            state: "digest",
            notification: %{"event" => "failed_job", "job" => %{"worker" => "MyApp.Job#{n}", "error" => "boom"}},
            inserted_at: DateTime.add(now, n, :microsecond),
            updated_at: now
          }
        end

      {201, _} = Repo.insert_all(Delivery, rows)
      due = Digest.next_at(:daily, now)

      states = fn ->
        Repo.all(from(d in Delivery, where: d.route_id == ^route.id, group_by: d.state, select: {d.state, count(d.id)}))
      end

      # The first batch goes out, and the rest is queued to go now, not at the next digest
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = Notes.deliver_mentions(reader.id, due)
        assert Enum.sort(states.()) == [{"digest", 1}, {"succeeded", 200}]
        assert [job] = all_enqueued(worker: Brando.Worker.NoteMentions, args: %{"user_id" => reader.id})
        assert DateTime.compare(job.scheduled_at, DateTime.utc_now()) != :gt

        # A new item meanwhile does not move it to the next digest
        assert {:ok, _} = Digest.schedule(reader.id)
        assert [job] = all_enqueued(worker: Brando.Worker.NoteMentions, args: %{"user_id" => reader.id})
        assert DateTime.compare(job.scheduled_at, DateTime.utc_now()) != :gt
      end)

      # Nor does one that came while the digest was being sent: the rest
      # brings its job forward
      Repo.update_all(from(d in Delivery, where: d.route_id == ^route.id), set: [state: "digest"])
      Repo.delete_all(from(j in Oban.Job, where: j.worker == "Brando.Worker.NoteMentions"))

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, %{state: "scheduled"} = waiting} = Digest.schedule(reader.id)
        hours_ago = DateTime.add(DateTime.utc_now(), -3 * 3600, :second)
        Repo.update_all(from(j in Oban.Job, where: j.id == ^waiting.id), set: [inserted_at: hours_ago])
        assert :ok = Notes.deliver_mentions(reader.id, due)
        assert [job] = all_enqueued(worker: Brando.Worker.NoteMentions, args: %{"user_id" => reader.id})
        assert DateTime.compare(job.scheduled_at, DateTime.utc_now()) != :gt
      end)

      assert :ok = Notes.deliver_mentions(reader.id, due)
      assert_email_sent(fn email -> email.text_body =~ "MyApp.Job201" end)
      assert states.() == [{"succeeded", 201}]
    end

    test "the rest of a full summary is queued to go now, or the running job retries", %{user: user} do
      reader = Factory.insert(:random_user, config: %UserConfig{notification_digest: :daily})
      _route = route!(user, %{"kind" => "email", "events" => ["failed_job"], "recipient_ids" => [reader.id]})

      Oban.Testing.with_testing_mode(:manual, fn ->
        # A job waiting to retry, hours from now, is brought forward
        {:ok, waiting} = Digest.schedule(reader.id)
        later = DateTime.add(DateTime.utc_now(), 3 * 3600, :second)
        Repo.update_all(from(j in Oban.Job, where: j.id == ^waiting.id), set: [state: "retryable", scheduled_at: later])

        assert :ok = Digest.schedule_rest(reader.id)
        assert [job] = Repo.all(from(j in Oban.Job, where: j.worker == "Brando.Worker.NoteMentions"))
        assert DateTime.compare(job.scheduled_at, DateTime.utc_now()) != :gt

        # So is one waiting for the next digest, and a new item does not
        # push it back there before it runs
        Repo.update_all(from(j in Oban.Job, where: j.id == ^waiting.id), set: [state: "scheduled", scheduled_at: later])
        assert :ok = Digest.schedule_rest(reader.id)
        assert {:ok, _} = Digest.schedule(reader.id)
        assert [job] = Repo.all(from(j in Oban.Job, where: j.worker == "Brando.Worker.NoteMentions"))
        assert job.state == "available"
        assert DateTime.compare(job.scheduled_at, DateTime.utc_now()) != :gt
      end)

      # Oban reports a unique insert that could not take its lock as a
      # conflict with nothing inserted: that is no queued job
      due_by = DateTime.utc_now()
      assert {:error, :locked} = Digest.rest_queued({:ok, %Oban.Job{conflict?: true, id: nil}}, due_by)
      assert :ok = Digest.rest_queued({:ok, %Oban.Job{id: 1, state: "available", scheduled_at: due_by}}, due_by)

      not_due = %Oban.Job{id: 1, conflict?: true, state: "scheduled", scheduled_at: DateTime.add(due_by, 3600)}
      assert {:error, :not_due} = Digest.rest_queued({:ok, not_due}, due_by)
    end

    test "notifications another job sent meanwhile are not sent again", %{user: user} do
      reader = Factory.insert(:random_user, config: %UserConfig{notification_digest: :daily})
      route = route!(user, %{"kind" => "email", "events" => ["failed_job"], "recipient_ids" => [reader.id]})
      now = DateTime.utc_now()

      Repo.insert!(%Delivery{
        route_id: route.id,
        recipient_id: reader.id,
        event: "failed_job",
        state: "digest",
        notification: %{"event" => "failed_job", "job" => %{"worker" => "MyApp.Once", "error" => "boom"}}
      })

      # Another job takes and sends them right after this one read them
      test = self()
      id = "digest-claim-#{System.unique_integer([:positive])}"

      :telemetry.attach(
        id,
        [:brando_integration, :repo, :query],
        fn _event, _measurements, meta, _config ->
          if self() == test and meta.source == "notification_deliveries" and
               String.starts_with?(meta.query, "SELECT") and !Process.get(id) do
            Process.put(id, true)
            Repo.update_all(from(d in Delivery, where: d.route_id == ^route.id), set: [state: "succeeded"])
          end
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(id) end)

      assert :ok = Notes.deliver_mentions(reader.id, Digest.next_at(:daily, now))
      assert_no_email_sent()
    end

    test "the rest that cannot be brought forward fails the job, not crashes it", %{user: user} do
      reader = Factory.insert(:random_user, config: %UserConfig{notification_digest: :daily})
      _route = route!(user, %{"kind" => "email", "events" => ["failed_job"], "recipient_ids" => [reader.id]})

      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, _waiting} = Digest.schedule(reader.id)

        # The database fails between joining the waiting job and making it available
        test = self()
        id = "retry-fails-#{System.unique_integer([:positive])}"

        :telemetry.attach(
          id,
          [:brando_integration, :repo, :query],
          fn _event, _measurements, meta, _config ->
            if self() == test and meta.source == "oban_jobs" and String.starts_with?(meta.query, "UPDATE") and
                 !Process.get(id) do
              Process.put(id, true)
              Repo.query!("ALTER TABLE oban_jobs RENAME TO oban_jobs_away")
            end
          end,
          nil
        )

        on_exit(fn -> :telemetry.detach(id) end)
        assert {:error, _} = Digest.schedule_rest(reader.id)
      end)
    end

    test "a summary item whose recipient could not be checked is marked so", %{user: user} do
      put_test_env(:authorization_mode, :groups)
      put_test_env(:tenancy_mode, :none)
      reader = Factory.insert(:random_user, role: :superuser, config: %UserConfig{notification_digest: :daily})
      {:ok, _} = Brando.Authorization.Migration.run()
      route = route!(user, %{"kind" => "email", "recipient_ids" => [reader.id]})
      page = Factory.insert(:page, creator: reader)

      delivery =
        Repo.insert!(%Delivery{
          route_id: route.id,
          recipient_id: reader.id,
          event: "scheduled_publish",
          state: "digest",
          entry_schema: to_string(Brando.AuthorizationTestResources.Page),
          entry_id: page.id,
          notification: %{"event" => "test"}
        })

      Process.put(:authorization_test_policy_raises, %RuntimeError{message: "association not loaded"})
      capture_log(fn -> assert :ok = Notes.deliver_mentions(reader.id, Digest.next_at(:daily, delivery.inserted_at)) end)

      assert %{state: "failed", error: "recipient_check_failed"} = Repo.reload!(delivery)
      assert_no_email_sent()
    end

    test "one email job waits per user, however long ago it was queued", %{user: user} do
      reader = Factory.insert(:random_user, config: %UserConfig{notification_digest: :daily})
      _route = route!(user, %{"kind" => "email", "events" => ["failed_job"], "recipient_ids" => [reader.id]})

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, first} = Digest.schedule(reader.id)
        hours_ago = DateTime.add(DateTime.utc_now(), -3 * 3600, :second)
        Repo.update_all(from(j in Oban.Job, where: j.id == ^first.id), set: [inserted_at: hours_ago])

        assert {:ok, _} = Digest.schedule(reader.id)
        assert [%{id: id}] = all_enqueued(worker: Brando.Worker.NoteMentions, args: %{"user_id" => reader.id})
        assert id == first.id
      end)
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
          receiver = WebhookReceiver.start()
          route = slack_route!(user, receiver)
          manual = slack_route!(user, receiver, %{"name" => "Off"})
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

  describe "who may get email" do
    setup do
      put_test_env(:tenancy_mode, :multi)
      prefix = "tenant_notify-b_production"

      {:ok, site} =
        Brando.Tenant.Registry.create_site(%{
          name: "Notify B",
          key: "notify-b",
          languages: ["en"],
          default_language: "en",
          status: :active,
          delivery_mode: :dynamic
        })

      Repo.query!(~s|CREATE SCHEMA "#{prefix}"|)

      for table <- ~w(notification_routes notification_deliveries) do
        Repo.query!(~s|CREATE TABLE "#{prefix}".#{table} (LIKE public.#{table} INCLUDING ALL)|)
      end

      {:ok, site: site, prefix: prefix}
    end

    test "only members of the site are offered, saved and sent to", %{user: user, site: site, prefix: prefix} do
      member = Factory.insert(:random_user, role: :user, name: "Member")
      outsider = Factory.insert(:random_user, role: :user, name: "Outsider")
      {:ok, _} = Brando.Tenant.Access.grant(member, site, :editor)

      Brando.Tenant.with_prefix(prefix, fn ->
        ids = Enum.map(Routing.recipient_options(), & &1.id)
        assert member.id in ids
        refute outsider.id in ids

        assert {:error, changeset} =
                 Routing.create_route(
                   %{"name" => "Desk", "kind" => "email", "events" => ["failed_job"], "recipient_ids" => [outsider.id]},
                   user
                 )

        assert changeset.errors[:recipient_ids]

        route = route!(user, %{"kind" => "email", "events" => ["failed_job"], "recipient_ids" => [member.id]})
        delivery = %Delivery{route_id: route.id, recipient_id: member.id, event: "failed_job"}
        assert Brando.Notifications.Recipient.may_see?(member, delivery, route)

        # No longer on the site: nothing more is sent, about entries or not
        :ok = Brando.Tenant.Access.revoke(member, site)
        refute Brando.Notifications.Recipient.may_see?(member, delivery, route)
        refute Brando.Notifications.Recipient.may_see?(outsider, delivery, %{route | recipient_ids: [outsider.id]})
      end)
    end
  end

  describe "hardening" do
    test "Teams text goes as plain text runs, and the Slack fallback is escaped" do
      n = %{
        "event" => "scheduled_publish",
        "entry" => %{"title" => "[Log in](https://evil.example.com) *now* _here_ `x` #1"}
      }

      [%{"content" => %{"body" => body}}] = Message.teams(n)["attachments"]

      # As it is, unescaped, in a run that reads no Markdown
      assert [%{"type" => "RichTextBlock", "inlines" => [%{"type" => "TextRun", "text" => title}]} | _] = body
      assert title == "Published as scheduled: [Log in](https://evil.example.com) *now* _here_ `x` #1"
      refute Enum.any?(body, &(&1["type"] == "TextBlock"))

      assert Message.slack(Map.put(n, "entry", %{"title" => "<https://evil|click>"}))["text"] ==
               "Published as scheduled: &lt;https://evil|click&gt;"
    end

    test "webhook URLs are limited to Slack's and Teams' hosts", %{user: user} do
      assert {:error, changeset} =
               Routing.create_route(
                 %{"name" => "Desk", "kind" => "slack", "events" => ["mention"], "url" => "https://hooks.example.com/x"},
                 user
               )

      assert {_, opts} = changeset.errors[:url]
      assert opts[:reason] == :host_not_allowed

      assert %Route{} =
               route!(user, %{
                 "kind" => "slack",
                 "events" => ["mention"],
                 "url" => "https://hooks.slack.com/services/T0/B0/x"
               })

      assert %Route{} =
               route!(user, %{
                 "kind" => "teams",
                 "events" => ["mention"],
                 "url" => "https://prod-01.westeurope.logic.azure.com/workflows/abc"
               })

      refute Route.allowed_host?(:teams, "https://hooks.slack.com/services/x")
      refute Route.allowed_host?(:slack, "https://hooks.slack.com.evil.example.com/x")
    end

    test "a route switched to email keeps no webhook URL", %{user: user} do
      receiver = WebhookReceiver.start()
      route = slack_route!(user, receiver)
      {:ok, email} = Routing.update_route(route, %{"kind" => "email", "recipient_ids" => [user.id]}, user)

      assert %{url_ciphertext: nil, url_hint: nil} = Repo.reload!(email)
    end

    test "failed jobs are notified once per worker in the interval, by the delivery log", %{user: user} do
      receiver = WebhookReceiver.start()
      route = slack_route!(user, receiver, %{"events" => ["failed_job"]})
      job = %{"worker" => "MyApp.Worker.Sync", "attempt" => 3, "max_attempts" => 3}

      assert :ok = Routing.job_failed(job)
      assert :ok = Routing.job_failed(job)
      assert :ok = Routing.job_failed(%{job | "worker" => "MyApp.Worker.Other"})
      assert length(deliveries(route)) == 2

      put_test_env(Brando.Notifications, failed_job_interval: 0)
      assert :ok = Routing.job_failed(job)
      assert length(deliveries(route)) == 3
    end

    test "a burst of the same event on a Slack route goes out as one message", %{user: user} do
      receiver = WebhookReceiver.start()
      route = slack_route!(user, receiver)
      pages = for n <- 1..3, do: create_page(user, %{title: "Launch #{n}"})

      Oban.Testing.with_testing_mode(:manual, fn ->
        Brando.Activity.with_source(:scheduler, fn ->
          for page <- pages, do: {:ok, _} = Pages.update_page(page.id, %{status: :published}, user)
        end)

        Oban.drain_queue(queue: :content_events)
      end)

      [first, second, third] = route |> deliveries() |> Enum.sort_by(& &1.id)
      args = &%{"delivery" => &1.id, "route" => route.id}

      assert :ok = NotificationDelivery.deliver(%Oban.Job{args: args.(first), attempt: 1, max_attempts: 10})
      body = Jason.decode!(next_request().body)
      assert body["text"] == "3 entries published as scheduled"
      text = hd(body["blocks"])["text"]["text"]
      assert text =~ "Launch 1"
      assert text =~ "Launch 3"

      assert %{state: "succeeded", grouped_into_id: id} = Repo.reload!(third)
      assert id == first.id

      assert {:cancel, _} =
               NotificationDelivery.deliver(%Oban.Job{args: args.(second), attempt: 1, max_attempts: 10})

      refute_receive {:webhook_request, _}, 100
    end

    test "email without a summary waits for the ten-minute batch", %{user: user} do
      reader = Factory.insert(:random_user)
      route = route!(user, %{"kind" => "email", "events" => ["failed_job"], "recipient_ids" => [reader.id]})

      assert :ok = Routing.job_failed(%{"worker" => "MyApp.A", "attempt" => 1, "max_attempts" => 1})
      assert_email_sent(fn email -> email.subject == "A background job failed: MyApp.A" end)

      # Within ten minutes: they wait, and go out together
      assert :ok = Routing.job_failed(%{"worker" => "MyApp.B", "attempt" => 1, "max_attempts" => 1})
      assert :ok = Routing.job_failed(%{"worker" => "MyApp.C", "attempt" => 1, "max_attempts" => 1})
      assert_no_email_sent()
      assert {:snooze, _} = Notes.deliver_mentions(reader.id)

      assert :ok = Notes.deliver_mentions(reader.id, DateTime.add(DateTime.utc_now(), 601, :second))

      assert_email_sent(fn email ->
        assert email.subject == "2 notifications"
        assert email.text_body =~ "MyApp.B"
        assert email.text_body =~ "MyApp.C"
      end)

      assert route |> deliveries() |> Enum.map(& &1.state) |> Enum.uniq() == ["succeeded"]
    end

    test "what waits is dropped when the route is paused or no longer names the user", %{user: user} do
      reader = Factory.insert(:random_user, config: %UserConfig{notification_digest: :daily})
      other = Factory.insert(:random_user, config: %UserConfig{notification_digest: :daily})
      route = route!(user, %{"kind" => "email", "events" => ["failed_job"], "recipient_ids" => [reader.id, other.id]})

      assert :ok = Routing.job_failed(%{"worker" => "MyApp.A", "attempt" => 1, "max_attempts" => 1})
      assert route |> deliveries() |> Enum.map(& &1.state) == ["digest", "digest"]

      {:ok, route} = Routing.update_route(route, %{"recipient_ids" => [other.id]}, user)
      later = DateTime.add(DateTime.utc_now(), 8 * 86_400, :second)
      assert :ok = Notes.deliver_mentions(reader.id, later)
      assert_no_email_sent()

      {:ok, _} = Routing.pause(route, user)
      assert :ok = Notes.deliver_mentions(other.id, later)
      assert_no_email_sent()

      assert route |> deliveries() |> Enum.map(&{&1.state, &1.error}) |> Enum.uniq() ==
               [{"cancelled", "recipient_unavailable"}]
    end
  end

  describe "bursts and redelivery" do
    defp pending!(route, title) do
      Repo.insert!(%Delivery{
        route_id: route.id,
        event: "scheduled_publish",
        notification: %{"event" => "scheduled_publish", "entry" => %{"title" => title}}
      })
    end

    defp job(delivery),
      do: %Oban.Job{args: %{"delivery" => delivery.id, "route" => delivery.route_id}, attempt: 1, max_attempts: 10}

    test "jobs running at once send a burst once", %{user: user} do
      receiver = WebhookReceiver.start(fn _ -> {200, "ok"} end)
      route = slack_route!(user, receiver)

      for round <- 1..3 do
        deliveries = for n <- 1..4, do: pending!(route, "Round #{round} entry #{n}")

        results =
          deliveries
          |> Enum.map(fn delivery -> Task.async(fn -> NotificationDelivery.deliver(job(delivery)) end) end)
          |> Task.await_many(10_000)

        assert Enum.all?(results, &(&1 == :ok or match?({:cancel, _}, &1)))
        sent = Enum.count(results, &(&1 == :ok))

        # One request per job that sent, and every entry in exactly one of them
        texts =
          for _ <- 1..sent do
            assert_receive {:webhook_request, request}, 5_000
            request.body |> Jason.decode!() |> Map.fetch!("blocks") |> hd() |> get_in(["text", "text"])
          end

        refute_receive {:webhook_request, _}, 200

        for n <- 1..4 do
          assert Enum.count(texts, &(&1 =~ "Round #{round} entry #{n}")) == 1
        end

        assert deliveries |> Enum.map(&Repo.reload!(&1).state) |> Enum.uniq() == ["succeeded"]
      end
    end

    test "a job whose delivery another job grouped meanwhile stops", %{user: user} do
      receiver = WebhookReceiver.start()
      route = slack_route!(user, receiver)
      [a, b] = [pending!(route, "A"), pending!(route, "B")]

      # B's job has loaded B while pending; A's job then sends both
      loaded_b = Repo.reload!(b)
      assert :ok = NotificationDelivery.deliver(job(a))
      assert_receive {:webhook_request, %{body: body}}, 5_000
      assert Jason.decode!(body)["text"] == "2 entries published as scheduled"

      # B's job may not take it now, so B is not sent again
      assert {:cancel, :already_claimed} = NotificationDelivery.claim(loaded_b)
      assert {:cancel, _} = NotificationDelivery.deliver(job(b))
      refute_receive {:webhook_request, _}, 100
      assert %{state: "succeeded", grouped_into_id: id} = Repo.reload!(b)
      assert id == a.id
    end

    test "redelivering a burst's main delivery sends the whole burst again, as one", %{user: user} do
      receiver = WebhookReceiver.start(fn _ -> {500, "down"} end)
      route = slack_route!(user, receiver)
      [main | _] = for n <- 1..3, do: pending!(route, "Entry #{n}")

      assert {:cancel, "HTTP 500"} =
               NotificationDelivery.deliver(%Oban.Job{job(main) | attempt: 10, max_attempts: 10})

      assert_receive {:webhook_request, _}, 5_000
      assert route |> deliveries() |> Enum.map(& &1.state) |> Enum.uniq() == ["failed"]

      {:ok, _} = Routing.resume(Repo.reload!(route), user)
      ok_receiver = WebhookReceiver.start()
      {:ok, route} = Routing.update_route(Repo.reload!(route), %{"url" => WebhookReceiver.url(ok_receiver, "/s")}, user)

      assert {:ok, again} = Routing.redeliver(Repo.reload!(main), user)
      assert_receive {:webhook_request, %{path: "/s", body: body}}, 5_000
      assert Jason.decode!(body)["text"] == "3 entries published as scheduled"

      grouped = Repo.all(from(d in Delivery, where: d.grouped_into_id == ^again.id))
      assert length(grouped) == 2
      assert Enum.all?([Repo.reload!(again) | grouped], &(&1.state == "succeeded"))
      assert length(deliveries(route)) == 6
    end
  end

  describe "the notifications queue" do
    test "is missing when Oban runs queues but not this one" do
      missing = Oban.Config.new(repo: BrandoIntegration.Repo, queues: [default: 1, webhooks: 5], plugins: false)
      running = Oban.Config.new(repo: BrandoIntegration.Repo, queues: [default: 1, notifications: 2], plugins: false)
      none = Oban.Config.new(repo: BrandoIntegration.Repo, queues: false, plugins: false)

      assert Routing.queue_missing?(missing)
      refute Routing.queue_missing?(running)
      # A node without queues cannot tell, nor can testing
      refute Routing.queue_missing?(none)
      refute Routing.queue_missing?()
    end

    test "the dashboard notice is for those who manage routes", %{user: user} do
      html = Phoenix.LiveViewTest.render_component(&BrandoAdmin.Components.Dashboard.notifications_queue_notice/1, %{})
      assert html =~ "dashboard-notifications-queue"
      assert html =~ "notifications: [limit: 2]"

      refute Routing.queue_warning?(Factory.insert(:random_user, role: :editor))
      # Oban runs inline in tests, so the queue counts as running
      refute Routing.queue_warning?(user)
    end
  end
end
