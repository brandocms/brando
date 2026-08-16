defmodule Brando.Plug.SSG do
  @moduledoc """
  Backwards-compatible no-op.

  Static output is now captured by `Brando.SSG.build/3` after ordinary HTTP
  responses, so applications may remove this plug from their browser pipeline.
  """

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts), do: conn
end
