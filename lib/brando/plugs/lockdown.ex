defmodule Brando.Plug.Lockdown do
  @moduledoc """
  Basic plug for locking down websites under development

  If we have an authenticated user, we are allowed in.

  ## Example

      plug Brando.Plug.Lockdown

  The `Lockdown` plug looks for a `lockdown_path` in your `router.ex`.

  ## Example

      scope "/coming-soon" do
        get "/", Brando.LockdownController, :index
        post "/", Brando.LockdownController, :post_password
      end

  ## Configure

      config :brando,
        lockdown: true,
        lockdown_password: "my_pass",
        lockdown_until: ~N[2015-01-13 13:00:07]

  Password is optional. If no password configuration is found, you have to login
  through the backend to see the frontend website.

  """
  alias Brando.User
  import Phoenix.Controller, only: [redirect: 2]
  import Plug.Conn, only: [halt: 1]

  @behaviour Plug

  @spec init(Keyword.t) :: Keyword.t
  def init(options), do: options

  @spec call(Plug.Conn.t, Keyword.t) :: Plug.Conn.t
  def call(conn, _) do
    if Brando.config(:lockdown) do
      conn
      |> allowed?
    else
      conn
    end
  end

  @spec allowed?(Plug.Conn.t) :: Plug.Conn.t
  defp allowed?(%{private: %{plug_session: %{"current_user" => user}}} = conn) do
    if User.can_login?(user) do
      conn
    else
      lockdown(conn)
    end
  end

  defp allowed?(%{private: %{plug_session: %{"lockdown_authorized" => true}}} = conn), do: conn
  defp allowed?(conn), do: lockdown(conn)

  @spec lockdown(Plug.Conn.t) :: Plug.Conn.t
  defp lockdown(conn) do
    check_lockdown_date(conn, Brando.config(:lockdown_until))
  end

  defp check_lockdown_date(conn, nil) do
    conn
    |> redirect(to: Brando.helpers.lockdown_path(conn, :index))
    |> halt
  end

  defp check_lockdown_date(conn, lockdown_until) do
    # TODO: replace with NaiveDateTime.compare/2 when elixir 1.4 is out
    if compare(lockdown_until, NaiveDateTime.from_erl!(:calendar.local_time)) == :gt do
      conn
      |> redirect(to: Brando.helpers.lockdown_path(conn, :index))
      |> halt
    else
      conn
    end
  end

  @doc """
  Compares two `NaiveDateTime` structs.
  Returns :gt if first is later than the second
  and :lt for vice versa. If the two NaiveDateTime
  are equal :eq is returned
  ## Examples
      iex> NaiveDateTime.compare(~N[2016-04-16 13:30:15], ~N[2016-04-28 16:19:25])
      :lt
      iex> NaiveDateTime.compare(~N[2016-04-16 13:30:15.1], ~N[2016-04-16 13:30:15.01])
      :gt

  TODO: REMOVE WITH ELIXIR 1.4!
  """
  @spec compare(NaiveDateTime.t, NaiveDateTime.t) :: :lt | :eq | :gt
  def compare(%NaiveDateTime{} = naive_datetime1, %NaiveDateTime{} = naive_datetime2) do
    case {to_tuple(naive_datetime1), to_tuple(naive_datetime2)} do
      {first, second} when first > second -> :gt
      {first, second} when first < second -> :lt
      _ -> :eq
    end
  end
  # TODO: REMOVE WITH ELIXIR 1.4!
  defp to_tuple(%NaiveDateTime{calendar: Calendar.ISO, year: year,
                               month: month, day: day, hour: hour,
                               minute: minute, second: second,
                               microsecond: {microsecond, _precision}}) do
    {year, month, day, hour, minute, second, microsecond}
  end
end
