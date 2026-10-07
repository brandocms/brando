defmodule Brando.Users.SecurityLog do
  @moduledoc """
  The log of sign-in security events (`Brando.Users.SecurityEvent`):
  sign-ins, failed sign-ins and lockouts, and changes to passwords and
  two-factor settings, with the IP address and browser they came from.

  Users are shared by every site, so the log lives in `public`, apart from the
  content activity log (`Brando.Activity`). It keeps events as long as that
  one does (`Brando.Activity.retention_days/0`), and the user's security page
  and an administrator's view of the user form show the latest.

  Recording never fails the action it records: an event that cannot be
  written is logged and dropped.
  """

  import Ecto.Query

  alias Brando.Repo
  alias Brando.Users.SecurityEvent
  alias Phoenix.LiveView

  require Logger

  @type meta :: %{optional(:ip) => String.t() | nil, optional(:user_agent) => String.t() | nil}

  @doc """
  Records `action` for `user` (a user, a user id or nil). Options:

    * `:actor` — who did it, when not the user themselves;
    * `:meta` — `%{ip:, user_agent:}` of the request, see `meta/1`;
    * `:details` — a map of facts about the event.
  """
  @spec record(atom(), map() | integer() | nil, keyword()) :: :ok
  def record(action, user, opts \\ []) do
    meta = Keyword.get(opts, :meta) || %{}

    attrs = %{
      action: action,
      user_id: id(user),
      actor_id: id(Keyword.get(opts, :actor)),
      ip: meta[:ip],
      user_agent: meta[:user_agent] && String.slice(meta[:user_agent], 0, 255),
      details: Keyword.get(opts, :details, %{})
    }

    insert_opts = if Repo.repo().in_transaction?(), do: [mode: :savepoint], else: []

    case %SecurityEvent{} |> Ecto.Changeset.change(attrs) |> Repo.insert(insert_opts) do
      {:ok, _event} -> :ok
      {:error, changeset} -> warn(inspect(changeset.errors))
    end
  rescue
    error -> warn(Exception.message(error))
  end

  defp warn(message) do
    Logger.warning("[Brando.Users.SecurityLog] Could not record a security event: " <> message)
    :ok
  end

  defp id(%{id: id}), do: id
  defp id(id) when is_integer(id), do: id
  defp id(_), do: nil

  @doc """
  The IP address and browser of a request, from a `Plug.Conn`, or from the
  `:peer_data`, `:x_headers` and `:user_agent` of a LiveView's connect info.
  The address is the client's behind a trusted proxy (`Brando.ClientIP`).
  """
  @spec meta(Plug.Conn.t() | map()) :: meta()
  def meta(%Plug.Conn{} = conn) do
    %{
      ip: ip_string(Brando.ClientIP.from_conn(conn)),
      user_agent: conn |> Plug.Conn.get_req_header("user-agent") |> List.first()
    }
  end

  def meta(%{} = info) do
    %{ip: ip_string(Brando.ClientIP.from_connect_info(info)), user_agent: info[:user_agent]}
  end

  @doc """
  `meta/1` of a connected LiveView socket, or nil before it connects. The
  socket's `connect_info` should give `:peer_data`, `:x_headers` and
  `:user_agent`; without them there is no address, and limits per IP
  address do not apply.
  """
  @spec socket_meta(Phoenix.LiveView.Socket.t()) :: meta() | nil
  def socket_meta(socket) do
    if LiveView.connected?(socket) do
      meta(%{
        peer_data: LiveView.get_connect_info(socket, :peer_data),
        x_headers: LiveView.get_connect_info(socket, :x_headers),
        user_agent: LiveView.get_connect_info(socket, :user_agent)
      })
    end
  end

  defp ip_string(nil), do: nil
  defp ip_string(address), do: address |> :inet.ntoa() |> to_string()

  @doc "The latest `limit` events of `user`, with whoever else acted."
  @spec list(map(), pos_integer()) :: [SecurityEvent.t()]
  def list(%{id: user_id}, limit \\ 10) do
    from(e in SecurityEvent,
      where: e.user_id == ^user_id,
      order_by: [desc: e.inserted_at, desc: e.id],
      limit: ^limit,
      preload: [:actor]
    )
    |> Repo.all()
  end

  @doc "Removes events older than `days`. Returns how many."
  @spec purge(pos_integer()) :: non_neg_integer()
  def purge(days \\ Brando.Activity.retention_days()) do
    cutoff = DateTime.add(DateTime.utc_now(), -days * 86_400, :second)
    {count, _} = Repo.delete_all(from(e in SecurityEvent, where: e.inserted_at < ^cutoff))
    count
  end
end
