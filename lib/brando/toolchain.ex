defmodule Brando.Toolchain do
  @node_major 24

  @moduledoc """
  The Node.js releases Brando's asset builds are tested on and accept, in one
  place for `mix brando.doctor` and `scripts/prepare_055_deps.exs`.

  The admin's packages declare `engines.node` as `>=24.0.0`, so an older
  major, the odd 23 among them, fails their engines check in pnpm installs.
  Odd releases are never LTS either. Brando is tested on Node #{@node_major};
  another even LTS major from there on works too.

  The module depends on nothing but Elixir: the script loads it with
  `Code.require_file/1` before the application's dependencies resolve.
  """

  @doc "The Node major Brando is tested on."
  @spec node_major() :: pos_integer()
  def node_major, do: @node_major

  @node_advice "Node #{@node_major} (or another even LTS major ≥ #{@node_major})"

  @doc "Which Node to use, as advice: \"#{@node_advice}\"."
  @spec node_advice() :: String.t()
  def node_advice, do: @node_advice

  @doc """
  The version `node --version` prints for the `node` on the PATH
  (`"v24.9.0"`), or nil when there is none or it fails.
  """
  @spec node_version() :: String.t() | nil
  def node_version do
    with node when is_binary(node) <- System.find_executable("node"),
         {output, 0} <- System.cmd(node, ["--version"], stderr_to_stdout: true) do
      String.trim(output)
    else
      _ -> nil
    end
  rescue
    _ -> nil
  end

  @doc """
  Whether a Node version (`"v24.9.0"` or `"24.9.0"`) is one to build
  Brando's assets with:

    * `:ok`
    * `{:odd, major}` - an odd release, which is not LTS
    * `{:old, major}` - a major before the tested one
    * `:unknown` - not a version this reads
  """
  @spec check_node(String.t()) :: :ok | {:odd, pos_integer()} | {:old, non_neg_integer()} | :unknown
  def check_node(version) do
    case Regex.run(~r/^v?(\d+)\./, String.trim(version)) do
      [_, major] -> classify(String.to_integer(major))
      nil -> :unknown
    end
  end

  defp classify(major) when rem(major, 2) == 1, do: {:odd, major}
  defp classify(major) when major < @node_major, do: {:old, major}
  defp classify(_major), do: :ok
end
