defmodule BrandoAdmin.Work do
  @moduledoc """
  Background work that reports to the admin user who started it.

  A job, or any other process, reports under a key and the user it works for:

      Work.start(user, "shopify-policies", gettext("Fetching policies from Shopify"))
      Work.update(user, "shopify-policies", gettext("Fetched 3 of 5"), percent: 60)
      Work.finish(user, "shopify-policies", gettext("Policies fetched"))
      Work.fail(user, "shopify-policies", gettext("Could not fetch the policies"))

  Where the user sees it depends on where they are:

    * **Inline.** A screen that shows the work itself renders it with
      `BrandoAdmin.Components.Work` (`work_button/1`, `work_status/1`) from
      the `@work` assign `on_mount BrandoAdmin.Work` keeps (see "LiveViews").
    * **As a toast.** On every other screen the admin shows a toast for the
      key: a spinner, or a bar when there is a `percent` or a count, which
      turns into the result when the work ends. Updates change that toast
      rather than stacking new ones. While the page shows the key inline (an
      element with its `data-work-id`), there is no toast for it, so the user
      is not told twice; `toast: :always` shows one anyway.

  The admin remembers running work (`BrandoAdmin.Work.Registry`): a screen
  opened or reloaded halfway shows it still running, and a new tab gets its
  toast. Work that hears nothing for `timeout` (15 minutes by default) is
  given up as failed, with `timed_out: true`, rather than spinning for ever.

  ## Oban jobs

  `track/4` makes a job report its own start, retries and outcome, with no
  change to the worker. The messages are written when the job is queued, in
  the language of the user queueing it:

      %{"build_id" => build.id}
      |> MyApp.Worker.Import.new()
      |> Work.track(user, "import",
        running: gettext("Importing products"),
        done: gettext("Products imported"),
        failed: gettext("Could not import the products")
      )
      |> Oban.insert()

  A job queued to run now starts the work when it is inserted, with
  `queued:` (or `running:`) as its message; a scheduled one starts when it
  runs.

  ## Several jobs as one piece of work

  Work started with `total:` counts its steps, and finishes when the last
  one reports with `advance/3`. Give each job of the batch
  `track(changeset, user, key, step: true)` and it advances the count when it
  succeeds or gives up. `done:` and `failed:` on `start/4` are the messages
  for the end: `failed` when any step failed.

      Work.start(user, "alt-text", gettext("Writing alt text"), total: 40,
        done: gettext("Alt text written"), failed: gettext("Some alt text could not be written"))

  Starting a key that is still running with `total:` adds to its count, so a
  second batch joins the first.

  ## Messages

  Messages are shown as given, so translate them in the user's language. A
  job runs in the default locale: `in_locale/2` runs a function in the
  user's.

  ## LiveViews

      on_mount BrandoAdmin.Work

  subscribes the LiveView to its user's work and keeps `@work`, a map of key
  to the latest `%BrandoAdmin.Work{}` in this site, including finished and
  failed work. A LiveView that defines `handle_work/2` (`work`, `socket`,
  returning the socket) is called after each change, to reload what the
  work changed.

  ## Keys and sites

  Keys are per user and per site: work started in one site's admin is not
  shown inline in another's. Its toast shows in whichever site the user is in.
  Work on something that belongs to no one site (a static build) passes
  `global: true` to every call, and shows inline in every site.
  """
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Work.Registry

  @default_timeout to_timeout(minute: 15)

  defstruct [
    :id,
    :key,
    :prefix,
    :user_id,
    :message,
    :percent,
    :total,
    :done_message,
    :failed_message,
    :started_at,
    :updated_at,
    status: :running,
    done: 0,
    failed: 0,
    toast: :auto,
    timeout: @default_timeout,
    timed_out: false
  ]

  @type status :: :running | :finished | :failed
  @type t :: %__MODULE__{
          id: String.t(),
          key: String.t(),
          prefix: String.t() | nil,
          user_id: integer(),
          status: status(),
          message: String.t() | nil,
          percent: number() | nil,
          done: non_neg_integer(),
          failed: non_neg_integer(),
          total: pos_integer() | nil,
          done_message: String.t() | nil,
          failed_message: String.t() | nil,
          toast: :auto | :always,
          timeout: pos_integer(),
          timed_out: boolean(),
          started_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @typedoc "A user, a user id, or `:system` (or nil), which reports nowhere"
  @type user :: %{id: integer()} | integer() | :system | nil

  @topic "brando:work"
  @meta_key "brando_work"

  @doc """
  Starts work under `key`.

  Options:

    * `:percent` — how far it has come, 0–100
    * `:total` — the number of steps (see "Several jobs as one piece of work")
    * `:done`, `:failed` — the messages when the last step is in
    * `:timeout` — how long without news before it is given up, in ms
    * `:toast` — `:always` to show a toast even where the page shows the
      work inline
    * `:global` — `true` for work that belongs to no one site (see "Keys and
      sites"); give it to every call for the key
  """
  @spec start(user(), String.t(), String.t(), keyword()) :: :ok
  def start(user, key, message, opts \\ []) do
    attrs =
      opts
      |> Keyword.take([:percent, :total, :timeout, :toast])
      |> Map.new()
      |> Map.merge(%{message: message, done_message: opts[:done], failed_message: opts[:failed]})
      |> put_scope(opts)

    report(user, key, :start, attrs)
  end

  @doc """
  Reports progress: a new message (nil keeps the last one) and `:percent`.
  Work that is not known yet starts.
  """
  @spec update(user(), String.t(), String.t() | nil, keyword()) :: :ok
  def update(user, key, message \\ nil, opts \\ []) do
    attrs =
      opts
      |> Keyword.take([:percent, :total, :done])
      |> Map.new()
      |> Map.put(:message, message)
      |> put_scope(opts)

    report(user, key, :update, attrs)
  end

  @doc "Counts one step of work started with `total:`, `:ok` or `:error`."
  @spec advance(user(), String.t(), :ok | :error, keyword()) :: :ok
  def advance(user, key, result \\ :ok, opts \\ []) when result in [:ok, :error] do
    report(user, key, :advance, put_scope(%{result: result}, opts))
  end

  @doc "The work is done. Takes `:global`."
  @spec finish(user(), String.t(), String.t() | nil, keyword()) :: :ok
  def finish(user, key, message \\ nil, opts \\ []),
    do: report(user, key, :finish, put_scope(%{message: message}, opts))

  @doc "The work failed, for good. Takes `:global`."
  @spec fail(user(), String.t(), String.t() | nil, keyword()) :: :ok
  def fail(user, key, message \\ nil, opts \\ []),
    do: report(user, key, :fail, put_scope(%{message: message}, opts))

  @doc """
  Marks an Oban job changeset so the job reports as work under `key`.

  Options:

    * `:queued` — the message from insert until the job runs (default
      `:running`)
    * `:running` — the message while it runs
    * `:done`, `:failed` — the messages when it ends (`:failed` also when
      Oban cancels or gives it up)
    * `:step` — `true` to count as a step of work started with `total:`
      instead (`advance/3`)
    * `:timeout`, `:toast`, `:global` — as for `start/4`
  """
  @spec track(Ecto.Changeset.t(), user(), String.t(), keyword()) :: Ecto.Changeset.t()
  def track(%Ecto.Changeset{} = changeset, user, key, opts \\ []) do
    case user_id(user) do
      nil ->
        changeset

      user_id ->
        work =
          %{
            "user_id" => user_id,
            "key" => key,
            "prefix" => if(opts[:global], do: nil, else: Brando.Tenant.current_prefix()),
            "step" => Keyword.get(opts, :step, false),
            "queued" => opts[:queued],
            "running" => opts[:running],
            "done" => opts[:done],
            "failed" => opts[:failed],
            "timeout" => opts[:timeout],
            "toast" => opts[:toast] && to_string(opts[:toast])
          }
          |> Map.reject(fn {_k, v} -> is_nil(v) end)

        meta = Ecto.Changeset.get_field(changeset, :meta) || %{}
        Ecto.Changeset.put_change(changeset, :meta, Map.put(meta, @meta_key, work))
    end
  end

  @doc "The latest state of running `key` for `user` in the current site, or nil. Takes `:global`."
  @spec get(user(), String.t(), keyword()) :: t() | nil
  def get(user, key, opts \\ []) do
    case user_id(user) do
      nil -> nil
      user_id -> Registry.get({user_id, prefix(opts), key})
    end
  end

  @doc "The user's running work in every site, oldest first."
  @spec list(user()) :: [t()]
  def list(user) do
    case user_id(user) do
      nil -> []
      user_id -> Registry.list(user_id)
    end
  end

  @doc "Subscribes the caller to `{:work, key, status, work}` for the user's work."
  @spec subscribe(user()) :: :ok
  def subscribe(user) do
    case user_id(user) do
      nil -> :ok
      user_id -> Phoenix.PubSub.subscribe(Brando.pubsub(), user_topic(user_id))
    end
  end

  @doc "Runs `fun` with the user's admin language as the Gettext locale."
  @spec in_locale(user(), (-> result)) :: result when result: var
  def in_locale(user, fun) do
    language =
      case user do
        %{language: language} when not is_nil(language) -> language
        user_id when is_integer(user_id) -> user_language(user_id)
        _ -> nil
      end

    Gettext.with_locale(Brando.Gettext, to_string(language || Brando.config(:default_admin_language) || "en"), fun)
  end

  @doc """
  The id of `key` in a site (nil for global work), as the page carries it
  in `data-work-id` and the toast is keyed.
  """
  @spec id(String.t() | nil, String.t()) :: String.t()
  def id(nil, key), do: key
  def id(prefix, key), do: prefix <> ":" <> key

  @doc "What the admin's JavaScript gets for a piece of work."
  @spec to_payload(t()) :: map()
  def to_payload(%__MODULE__{} = work) do
    %{
      id: work.id,
      status: work.status,
      # Nil when it has none: the registry has no user's locale to word one
      # in, so the page does (`data-work-*` on the body)
      message: work.message,
      percent: percent(work),
      done: work.done,
      failed: work.failed,
      total: work.total,
      toast: work.toast,
      timed_out: work.timed_out
    }
  end

  @doc "Whether `work` is running; false for nil."
  @spec running?(t() | nil) :: boolean()
  def running?(%__MODULE__{status: :running}), do: true
  def running?(_work), do: false

  @doc "How far the work has come, 0–100, from `percent` or its count; nil when unknown."
  @spec percent(t()) :: number() | nil
  def percent(%__MODULE__{percent: percent}) when is_number(percent), do: min(max(percent, 0), 100)

  def percent(%__MODULE__{total: total, done: done}) when is_integer(total) and total > 0,
    do: round(min(done / total, 1) * 100)

  def percent(_work), do: nil

  @doc "What the work says, in the current locale, when it ended without a message of its own."
  @spec fallback_message(t()) :: String.t() | nil
  def fallback_message(%__MODULE__{timed_out: true}), do: gettext("Stopped reporting progress")
  def fallback_message(%__MODULE__{status: :finished}), do: gettext("Done")
  def fallback_message(%__MODULE__{status: :failed}), do: gettext("Failed")
  def fallback_message(_work), do: nil

  @doc false
  def topic, do: @topic

  @doc false
  def user_topic(user_id), do: "#{@topic}:#{user_id}"

  @doc false
  def meta_key, do: @meta_key

  @doc false
  def default_timeout, do: @default_timeout

  # Every node's registry applies the event, and tells its own LiveViews and
  # channels, so nothing is sent twice in a cluster.
  @doc false
  def report(user, key, op, attrs) when is_binary(key) do
    case user_id(user) do
      nil ->
        :ok

      user_id ->
        prefix = Map.get_lazy(attrs, :prefix, &Brando.Tenant.current_prefix/0)
        event = {op, {user_id, prefix, key}, Map.delete(attrs, :prefix), DateTime.utc_now()}
        Phoenix.PubSub.broadcast(Brando.pubsub(), @topic, {:brando_work, event})
    end
  end

  defp put_scope(attrs, opts), do: Map.put(attrs, :prefix, prefix(opts))

  defp prefix(opts), do: if(opts[:global], do: nil, else: Brando.Tenant.current_prefix())

  @doc false
  def user_id(%{id: id}) when is_integer(id), do: id
  def user_id(id) when is_integer(id), do: id
  def user_id(_system), do: nil

  defp user_language(user_id) do
    import Ecto.Query, only: [from: 2]

    Brando.Repo.one(from(u in Brando.Users.User, where: u.id == ^user_id, select: u.language))
  end

  # LiveView hook: `on_mount BrandoAdmin.Work`

  @doc false
  def on_mount(:default, _params, _session, socket) do
    user = socket.assigns[:current_user]

    socket =
      if Phoenix.LiveView.connected?(socket) and user do
        subscribe(user)
        Phoenix.LiveView.attach_hook(socket, :brando_work, :handle_info, &handle_work_info/2)
      else
        socket
      end

    work = Map.new(if(user, do: list_here(user), else: []), &{&1.key, &1})
    {:cont, Phoenix.Component.assign(socket, :work, work)}
  end

  # This site's work, and global work
  defp list_here(user) do
    prefix = Brando.Tenant.current_prefix()
    user |> list() |> Enum.filter(&(&1.prefix in [nil, prefix]))
  end

  defp handle_work_info({:work, key, _status, %__MODULE__{prefix: prefix} = work}, socket) do
    if prefix in [nil, Brando.Tenant.current_prefix()] do
      socket = Phoenix.Component.update(socket, :work, &Map.put(&1 || %{}, key, work))

      socket =
        if function_exported?(socket.view, :handle_work, 2),
          do: socket.view.handle_work(work, socket),
          else: socket

      {:halt, socket}
    else
      {:halt, socket}
    end
  end

  defp handle_work_info(_message, socket), do: {:cont, socket}
end
