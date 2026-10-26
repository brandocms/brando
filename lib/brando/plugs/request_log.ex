defmodule Brando.Plug.RequestLog do
  @moduledoc """
  Keeps the secret tokens some of Brando's paths carry out of the request
  log: a shared preview's key (`/__p__/…`), a static site preview's token
  (`/__ssg_preview__/…`), a password reset link, a content transfer
  download and a shared assistant conversation. Anyone who reads the log
  could otherwise open them.

  Phoenix logs each request's method and path when the endpoint's
  `Plug.Telemetry` starts, at the level its `:log` option gives. Pointed
  here, the option logs those paths with the token replaced by
  `[FILTERED]`, and every other request as before:

      plug Plug.Telemetry,
        event_prefix: [:phoenix, :endpoint],
        log: {Brando.Plug.RequestLog, :level, []}

  `mix brando.install` writes this. The parameters Phoenix logs for the
  matched route are filtered by `config :phoenix, :filter_parameters`.
  """
  require Logger

  @filtered "[FILTERED]"

  # A path whose segments start with (or, below the admin's path, contain)
  # one of these has a secret token in the segment after it.
  @at_root [["__p__"], ["__ssg_preview__"]]
  @anywhere [["reset-password"], ["content-transfer", "download"], ["assistant", "shared"]]

  @doc """
  The log level of `conn`'s request: `level`, or `false` for a path with a
  token, which is logged here with the token filtered out instead. Phoenix
  calls it when the request starts and again when it ends; the end of such a
  request is not logged.
  """
  @spec level(Plug.Conn.t(), Logger.level()) :: Logger.level() | false
  def level(%Plug.Conn{} = conn, level \\ :info) do
    case filter(conn.path_info) do
      nil ->
        level

      path_info ->
        if conn.state == :unset, do: Logger.log(level, [conn.method, ?\s, "/", Enum.join(path_info, "/")])
        false
    end
  end

  @doc "`path_info` with its secret token filtered out, or `nil` when it has none."
  @spec filter([String.t()]) :: [String.t()] | nil
  def filter(path_info) do
    Enum.find_value(@at_root, &replace_after(path_info, &1)) || filter_below(path_info)
  end

  defp filter_below([]), do: nil

  defp filter_below([segment | rest] = path_info) do
    case Enum.find_value(@anywhere, &replace_after(path_info, &1)) do
      nil ->
        case filter_below(rest) do
          nil -> nil
          filtered -> [segment | filtered]
        end

      filtered ->
        filtered
    end
  end

  defp replace_after(path_info, marker) do
    case Enum.split(path_info, length(marker)) do
      {^marker, [_token | rest]} -> marker ++ [@filtered | rest]
      _ -> nil
    end
  end
end
