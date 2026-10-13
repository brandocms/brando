defmodule Brando.Toolchain do
  @node_major 22
  # The oldest release of the tested major Vite 8 accepts.
  @node_minimum {22, 12}

  @moduledoc """
  The Node.js releases Brando's asset builds are tested on and accept, in one
  place for `mix brando.doctor` and `scripts/prepare_055_deps.exs`.

  Vite 8 and the asset packages declare `engines.node` as
  `^20.19.0 || ^22.12.0 || >=24.0.0`, so an odd release such as 23 fails
  their engines check in pnpm and yarn installs; odd releases are never LTS
  either. Node 20 reached its end of life in April 2026. Brando is tested on
  Node #{@node_major}; another even LTS major from there on works too.

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
  (`"v22.15.0"`), or nil when there is none or it fails.
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
  Whether a Node version (`"v22.15.0"` or `"22.15.0"`) is one to build
  Brando's assets with:

    * `:ok`
    * `{:odd, major}` - an odd release: not LTS, and outside the asset
      packages' `engines.node`
    * `{:old, major}` - a major before the tested one
    * `{:below_minimum, "22.12"}` - the tested major, but older than Vite 8
      accepts
    * `:unknown` - not a version this reads
  """
  @spec check_node(String.t()) ::
          :ok | {:odd, pos_integer()} | {:old, non_neg_integer()} | {:below_minimum, String.t()} | :unknown
  def check_node(version) do
    case Regex.run(~r/^v?(\d+)\.(\d+)/, String.trim(version)) do
      [_, major, minor] -> classify(String.to_integer(major), String.to_integer(minor))
      nil -> :unknown
    end
  end

  defp classify(major, _minor) when rem(major, 2) == 1, do: {:odd, major}
  defp classify(major, _minor) when major < @node_major, do: {:old, major}

  defp classify(major, minor) do
    {minimum_major, minimum_minor} = @node_minimum

    if major == minimum_major and minor < minimum_minor,
      do: {:below_minimum, "#{minimum_major}.#{minimum_minor}"},
      else: :ok
  end
end
