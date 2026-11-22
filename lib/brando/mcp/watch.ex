defmodule Brando.MCP.Watch do
  @moduledoc """
  The live page of a connection: what a connected tool does on the site as
  it happens, at `/admin/assistant/connected/live/<connection>`
  (`BrandoAdmin.MCP.WatchLive`), for the connection's person and those who
  manage connected tools.

  `Brando.MCP.Tools` tells it each call twice, on the connection's topic:
  when the call starts, and when it ends, where the call is written to
  Activity, with the same summary (`summary/4`) the Activity event keeps. So
  the page opens on the connection's recent calls from Activity (`history/1`)
  and follows the rest live, from one source.

  The link (`url/1`) lasts as long as the connection. The person gets it from
  the server's instructions (`Brando.MCP.Server.instructions/2`), from
  `prepare_proposal`'s result as `watch_url`, next to `review_url`, and from
  the first result of a call after a quiet period of 30 minutes, for clients
  that do not show the instructions (`due?/1`). Each node remembers when it
  last gave it in the `:cache` Cachex cache, so a call writes nothing more to
  the database for it; another node may give it once more.
  """
  import Ecto.Query, only: [from: 2]

  alias Brando.Activity.Event
  alias Brando.MCP
  alias Brando.MCP.Grant

  @quiet :timer.minutes(30)
  @history_limit 50
  @history_seconds 3_600
  @text_limit 120
  @error_limit 300

  # The arguments a call's line names (`BrandoAdmin.Components.ToolSteps`)
  @inputs ~w(query content_type module name kind offset filename)

  @doc "The path of `grant`'s live page in the admin."
  @spec path(Grant.t() | integer()) :: String.t()
  def path(%Grant{id: id}), do: path(id)
  def path(id) when is_integer(id), do: "/admin/assistant/connected/live/#{id}"

  @doc "The address of `grant`'s live page."
  @spec url(Grant.t()) :: String.t()
  def url(grant) do
    Brando.endpoint().url() <> path(grant)
  rescue
    _ -> path(grant)
  end

  @doc "The PubSub topic of the calls of the connection `grant_id`."
  @spec topic(integer()) :: String.t()
  def topic(grant_id), do: "mcp_watch:#{grant_id}"

  @doc """
  Subscribes the caller to the calls of the connection `grant_id`. Each comes
  as `{Brando.MCP.Watch, call}`, a map with `:id` (the same at start and
  end), `:tool`, `:state` (`:running`, `:ok` or `:error`), `:at`, and at the
  end `:event_id` (the Activity event, nil when it could not be written),
  `:duration_ms` and `:details`. `{Brando.MCP.Watch, :ended}` comes when the
  connection is revoked.
  """
  @spec subscribe(integer()) :: :ok | {:error, term()}
  def subscribe(grant_id), do: Phoenix.PubSub.subscribe(Brando.pubsub(), topic(grant_id))

  @doc "Stops the caller's `subscribe/1` to the connection `grant_id`."
  @spec unsubscribe(integer()) :: :ok
  def unsubscribe(grant_id), do: Phoenix.PubSub.unsubscribe(Brando.pubsub(), topic(grant_id))

  @doc """
  Tells the connection `grant_id`'s page that call `id` of `tool` started,
  with `args` (`Brando.MCP.Tools`).
  """
  @spec started(integer(), String.t(), String.t(), map()) :: :ok
  def started(grant_id, id, tool, args) do
    broadcast(grant_id, %{
      id: id,
      tool: tool,
      state: :running,
      at: DateTime.utc_now(),
      details: %{"input" => input(args)}
    })
  end

  @doc """
  Tells the connection `grant_id`'s page that call `id` ended, with the
  `details` written to Activity and the insert's result (`recorded`): its
  event's id and time, or none when it could not be written.
  """
  @spec finished(integer(), String.t(), map(), {:ok, Event.t()} | {:error, term()}) :: :ok
  def finished(grant_id, id, details, {:ok, %Event{} = event}),
    do: broadcast(grant_id, call(id, event.id, event.inserted_at, details))

  # Not in Activity, but still on the page
  def finished(grant_id, id, details, _not_recorded),
    do: broadcast(grant_id, call(id, nil, DateTime.utc_now(), details))

  @doc "Tells the connection `grant_id`'s page that it was revoked: nothing more will come."
  @spec ended(integer()) :: :ok
  def ended(grant_id) do
    Phoenix.PubSub.broadcast(Brando.pubsub(), topic(grant_id), {__MODULE__, :ended})
    :ok
  end

  defp broadcast(grant_id, call) do
    Phoenix.PubSub.broadcast(Brando.pubsub(), topic(grant_id), {__MODULE__, call})
    :ok
  end

  @doc """
  The connection `grant`'s calls from Activity of the last hour, at most 50,
  newest first, as `subscribe/1` delivers them.
  """
  @spec history(Grant.t()) :: [map()]
  def history(%Grant{} = grant) do
    since = DateTime.add(DateTime.utc_now(), -@history_seconds, :second)
    schema = to_string(Grant)

    MCP.in_tenant(MCP.grant_tenant(grant), fn ->
      from(e in Event,
        where: e.action == :tool_called and e.schema == ^schema and e.entry_id == ^grant.id and e.inserted_at >= ^since,
        order_by: [desc: e.id],
        limit: @history_limit
      )
      |> Brando.Repo.all()
      |> Enum.map(&call("event-#{&1.id}", &1.id, &1.inserted_at, &1.details))
    end)
  end

  defp call(id, event_id, at, details) do
    %{
      id: id,
      event_id: event_id,
      tool: details["tool"],
      state: if(details["ok"] == false, do: :error, else: :ok),
      at: at,
      duration_ms: details["duration_ms"],
      details: details
    }
  end

  ## The link after a quiet period

  @doc """
  Whether the connection `grant_id` has made no call in 30 minutes, here:
  its next result carries the link. `delivered/1` starts the quiet period
  again.
  """
  @spec due?(integer()) :: boolean()
  def due?(grant_id) do
    case Cachex.get(:cache, key(grant_id)) do
      {:ok, nil} -> true
      {:ok, _} -> false
      _ -> false
    end
  end

  @doc "Notes a call of the connection `grant_id` that is not due the link, or that carried it."
  @spec delivered(integer()) :: :ok
  def delivered(grant_id) do
    Cachex.put(:cache, key(grant_id), true, expire: @quiet)
    :ok
  end

  @doc "Forgets the connection `grant_id`'s last call, as 30 quiet minutes would: its next result carries the link."
  @spec forget(integer()) :: :ok
  def forget(grant_id) do
    Cachex.del(:cache, key(grant_id))
    :ok
  end

  defp key(grant_id), do: {__MODULE__, :quiet, grant_id}

  ## What a call did

  @doc """
  What the live page shows of a call of tool `name` (the full MCP name) with
  `args`, which ended with `ok?` and the tool's structured result `data`
  (string keys): the arguments and the part of the result its line names
  (`"input"`, `"output"`), the error, the images an import or upload added
  or reused and their folder, and the proposal it stored, cancelled or previewed. Strings are cut short; no
  whole argument or result is kept. Written to the Activity event's details.
  """
  @spec summary(String.t(), map(), boolean(), map()) :: map()
  def summary(name, args, ok?, data) do
    output = if ok?, do: output(short_name(name), data), else: %{}

    %{"input" => input(args), "output" => output}
    |> Map.merge(if ok?, do: extras(short_name(name), data), else: %{"error" => cut(data["error"], @error_limit)})
    |> Map.reject(fn {_key, value} -> value in [nil, %{}] end)
  end

  @doc "A tool's name without `brando_content_`, `brando_figma_` or `brando_media_`."
  @spec short_name(String.t() | nil) :: String.t()
  def short_name("brando_content_" <> name), do: name
  def short_name("brando_figma_" <> name), do: name
  def short_name("brando_media_" <> name), do: name
  def short_name(name) when is_binary(name), do: name
  def short_name(_name), do: ""

  defp input(args) do
    for {key, value} <- Map.take(args, @inputs), value = simple(value), not is_nil(value), into: %{}, do: {key, value}
  end

  defp simple(value) when is_binary(value), do: cut(value, @text_limit)
  defp simple(value) when is_integer(value), do: value
  defp simple(_value), do: nil

  defp output("entry_outline", %{"title" => title}), do: %{"title" => cut(title, @text_limit)}

  defp output("prepare_proposal", data) do
    output = %{"version" => integer(data["version"]), "applicable" => data["applicable"] == true}

    case data["effects"] do
      %{"replaced_images" => count} when is_integer(count) and count > 0 -> Map.put(output, "replaced_images", count)
      _ -> output
    end
  end

  defp output("read_frame", data), do: %{"frame" => frame_name(data)}

  defp output("import_images", data),
    do: %{"frame" => frame_name(data), "images" => Enum.count(images(data), &Map.has_key?(&1, "id"))}

  # The host of an imported address, not the address: its query may hold a key
  defp output(name, data) when name in ["finish_upload", "import_url"],
    do: %{"images" => length(media_images(data)), "reused" => data["reused"] == true}

  defp output("list_proposals", %{"proposals" => proposals}) when is_list(proposals),
    do: %{"proposals" => length(proposals)}

  defp output("cancel_proposal", data), do: %{"version" => integer(data["version"])}

  # Which version it showed; the link itself is not kept: it opens the page without a login
  defp output("preview_proposal", data),
    do: %{"shows" => if(data["shows"] in ["proposed", "before"], do: data["shows"])}

  defp output(_name, _data), do: %{}

  defp extras("prepare_proposal", data) do
    %{"proposal" => if(is_binary(data["proposal_id"]), do: data["proposal_id"]), "preview" => local(data["preview_url"])}
  end

  defp extras("import_images", data) do
    images = images(data)
    imported = Enum.filter(images, &Map.has_key?(&1, "id"))

    %{
      "folder" => cut(data["folder"], @text_limit),
      "images" => imported,
      "failed" => if(length(imported) < length(images), do: length(images) - length(imported))
    }
  end

  defp extras(name, data) when name in ["finish_upload", "import_url"],
    do: %{"folder" => cut(data["folder"], @text_limit), "images" => media_images(data)}

  defp extras(name, data) when name in ["cancel_proposal", "preview_proposal"],
    do: %{"proposal" => if(is_binary(data["proposal_id"]), do: data["proposal_id"])}

  defp extras(_name, _data), do: %{}

  defp media_images(%{"asset" => %{"id" => id}} = data) when is_integer(id),
    do: [%{"id" => id, "reused" => data["reused"] == true}]

  defp media_images(_data), do: []

  defp images(%{"images" => images}) when is_list(images) do
    Enum.map(images, fn
      %{"asset" => %{"id" => id}} = image when is_integer(id) -> %{"id" => id, "reused" => image["reused"] == true}
      _ -> %{}
    end)
  end

  defp images(_data), do: []

  defp frame_name(%{"frame" => %{"name" => name}}), do: cut(name, @text_limit)
  defp frame_name(_data), do: nil

  # The path and query of an admin address, so the page links within itself
  defp local(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{path: "/admin/" <> _ = path, query: nil} -> path
      %URI{path: "/admin/" <> _ = path, query: query} -> path <> "?" <> query
      _ -> nil
    end
  end

  defp local(_url), do: nil

  defp integer(value) when is_integer(value), do: value
  defp integer(_value), do: nil

  defp cut(value, limit) when is_binary(value), do: String.slice(value, 0, limit)
  defp cut(_value, _limit), do: nil
end
