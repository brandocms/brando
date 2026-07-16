defmodule Brando.Media.URL do
  @moduledoc """
  Lightweight URL helpers for paths below Brando's configured media URL.
  """

  alias Brando.RuntimeConfig

  @doc """
  Returns the configured media URL.
  """
  @spec base() :: binary()
  def base, do: RuntimeConfig.get(:media_url)

  @doc """
  Prefixes a relative media path with the configured media URL.
  """
  @spec resolve(binary() | nil) :: binary()
  def resolve(nil), do: base()
  def resolve(path), do: Path.join([base(), path])
end
