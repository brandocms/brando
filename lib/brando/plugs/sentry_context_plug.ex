defmodule Brando.Plug.SentryUserContext do
  @moduledoc """
  Add user context to Sentry reporting
  """
  def init(opts), do: opts

  def call(conn, _opts), do: set_context(conn)

  defp set_context(%{private: %{guardian_default_resource: nil}} = conn), do: conn
  defp set_context(%{private: %{guardian_default_resource: user}} = conn) do
    # TODO: reenable?
    # Sentry.Context.set_user_context(%{
    #   id: user.id,
    #   email: user.email,
    #   name: user.full_name
    # })

    conn
  end

  defp set_context(conn), do: conn
end
