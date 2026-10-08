defmodule Brando.Notifications.Message do
  @moduledoc """
  What a notification says, and its shapes for Slack and Microsoft Teams.

  A notification is a map with string keys, stored on its delivery
  (`Brando.Notifications.Delivery`):

    * `"event"` — `"mention"`, `"scheduled_publish"`, `"scheduled_unpublish"`,
      `"failed_job"` or `"test"`;
    * `"site"` and `"environment"`, the keys it happened in;
    * `"entry"` — `%{"title", "type", "language", "admin_url"}` for an event
      about an entry, else nil;
    * for a mention, `"author"`, `"mentioned"` (names) and `"anchor"`, where
      in the entry the note is; never the note's text;
    * for a failed job, `"job"` (`"worker"`, `"queue"`, `"attempt"`,
      `"max_attempts"`, `"error"`), or `"webhook"` (`"name"`, `"host"`,
      `"admin_url"`) for a webhook delivery that failed for good.

  `content/2` words it in a language: a title, a line of text, a link into
  the admin and a context line naming the site and environment. `slack/1`
  and `teams/1` make the request bodies, in the site's default admin
  language.
  """
  use Gettext, backend: Brando.Gettext

  @type content :: %{
          title: String.t(),
          text: String.t() | nil,
          link: String.t() | nil,
          link_label: String.t(),
          context: String.t() | nil
        }

  @doc "The notification's words in `language`."
  @spec content(map(), String.t() | atom() | nil) :: content()
  def content(notification, language \\ nil) do
    Gettext.with_locale(Brando.Gettext, to_string(language || default_language()), fn ->
      {title, text, link} = words(notification)

      %{
        title: title,
        text: text,
        link: link,
        link_label: gettext("Open in the admin"),
        context: context(notification)
      }
    end)
  end

  @doc "The language Slack and Teams messages are written in: the site's default admin language."
  def default_language, do: to_string(Brando.config(:default_admin_language) || "en")

  defp words(%{"event" => "mention"} = n) do
    entry = n["entry"] || %{}
    names = n |> Map.get("mentioned", []) |> List.wrap() |> Enum.join(", ")

    title =
      if n["author"],
        do:
          gettext("%{author} mentioned %{names} in a note on %{title}",
            author: n["author"],
            names: names,
            title: entry["title"]
          ),
        else: gettext("%{names} was mentioned in a note on %{title}", names: names, title: entry["title"])

    text = if n["anchor"] not in [nil, ""], do: gettext("On %{place}", place: n["anchor"])
    {title, join([text, entry_details(entry)]), entry["admin_url"]}
  end

  defp words(%{"event" => "scheduled_publish"} = n) do
    entry = n["entry"] || %{}
    {gettext("Published as scheduled: %{title}", title: entry["title"]), entry_details(entry), entry["admin_url"]}
  end

  defp words(%{"event" => "scheduled_unpublish"} = n) do
    entry = n["entry"] || %{}
    {gettext("Unpublished as scheduled: %{title}", title: entry["title"]), entry_details(entry), entry["admin_url"]}
  end

  defp words(%{"event" => "failed_job", "webhook" => %{} = webhook}) do
    {gettext("A webhook stopped: %{name}", name: webhook["name"]),
     gettext("Deliveries to %{host} kept failing for a day, so the webhook was paused.", host: webhook["host"]),
     webhook["admin_url"]}
  end

  defp words(%{"event" => "failed_job"} = n) do
    job = n["job"] || %{}

    attempts =
      gettext("Given up after %{attempt} of %{max} attempts.", attempt: job["attempt"], max: job["max_attempts"])

    {gettext("A background job failed: %{worker}", worker: short_worker(job["worker"])), join([attempts, job["error"]]),
     nil}
  end

  defp words(%{"event" => "test"} = n) do
    {gettext("Test notification from %{site}", site: n["site"]), gettext("Notifications on this route arrive like this."),
     n["admin_url"]}
  end

  defp words(n), do: {to_string(n["event"]), nil, nil}

  defp entry_details(entry) do
    [entry["type"], entry["language"] && String.upcase(entry["language"])]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
    |> blank_to_nil()
  end

  defp context(n) do
    [n["site"], n["environment"]] |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join(" · ") |> blank_to_nil()
  end

  defp short_worker(nil), do: "?"
  defp short_worker(worker), do: worker |> to_string() |> String.replace_prefix("Elixir.", "")

  defp join(parts), do: parts |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join(" · ") |> blank_to_nil()

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  ## Slack

  @doc """
  The body for a Slack incoming webhook: a `text` fallback for
  notifications, and blocks — the title in bold with its text and link, and
  a context line with the site and environment.
  """
  @spec slack(map()) :: map()
  def slack(notification) do
    c = content(notification)

    lines =
      ["*" <> slack_escape(c.title) <> "*", c.text && slack_escape(c.text), c.link && slack_link(c.link, c.link_label)]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

    context =
      if c.context,
        do: [%{"type" => "context", "elements" => [%{"type" => "mrkdwn", "text" => slack_escape(c.context)}]}],
        else: []

    %{
      "text" => c.title,
      "blocks" => [%{"type" => "section", "text" => %{"type" => "mrkdwn", "text" => lines}} | context]
    }
  end

  # Slack reads `&`, `<` and `>` as markup: a title must not make a link.
  defp slack_escape(text) do
    text |> String.replace("&", "&amp;") |> String.replace("<", "&lt;") |> String.replace(">", "&gt;")
  end

  defp slack_link(url, label), do: "<" <> String.replace(url, "|", "%7C") <> "|" <> slack_escape(label) <> ">"

  ## Teams

  @doc """
  The body for a Microsoft Teams incoming webhook (a Workflows "post to a
  channel when a webhook request is received" flow): a message with one
  Adaptive Card — the title, its text, the context line, and a button to
  open the entry in the admin.
  """
  @spec teams(map()) :: map()
  def teams(notification) do
    c = content(notification)

    body =
      [
        %{"type" => "TextBlock", "text" => c.title, "weight" => "Bolder", "size" => "Medium", "wrap" => true},
        c.text && %{"type" => "TextBlock", "text" => c.text, "wrap" => true},
        c.context && %{"type" => "TextBlock", "text" => c.context, "isSubtle" => true, "size" => "Small", "wrap" => true}
      ]
      |> Enum.reject(&is_nil/1)

    card =
      %{
        "$schema" => "http://adaptivecards.io/schemas/adaptive-card.json",
        "type" => "AdaptiveCard",
        "version" => "1.4",
        "body" => body
      }
      |> then(fn card ->
        if c.link,
          do: Map.put(card, "actions", [%{"type" => "Action.OpenUrl", "title" => c.link_label, "url" => c.link}]),
          else: card
      end)

    %{
      "type" => "message",
      "attachments" => [
        %{"contentType" => "application/vnd.microsoft.card.adaptive", "contentUrl" => nil, "content" => card}
      ]
    }
  end
end
