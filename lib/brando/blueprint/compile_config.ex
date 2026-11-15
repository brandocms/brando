defmodule Brando.Blueprint.CompileConfig do
  @moduledoc false

  # Configuration a Blueprint compiles in: the installation's languages become
  # the `language` field's `Ecto.Enum` values, and an asset's literal `cfg`
  # merges the configured `default_config`. A plain read is invisible to Mix,
  # so a Brando installed from Hex or Git kept the old values after a config
  # change (brandocms/brando#3576).
  #
  # `read/1` reads a value and records its path for the file being compiled
  # (each file compiles in its own process). `track/1` runs at the end of each
  # Blueprint and reports the recorded paths through
  # `Application.compile_env/4`, so Mix stores the values used: it recompiles
  # the modules that read a changed value, and a dependency whose stored values
  # no longer match is recompiled before the project boots.
  #
  # A value changed after compilation, by `config/runtime.exs`, is a different
  # case: a release refuses to boot with Elixir's own message, and under Mix
  # `check!/0` (from `Brando.System.initialize/0`) raises with ours.

  alias Brando.Exception.ConfigError

  @app :brando
  @reads {__MODULE__, :reads}
  # The asset contexts by name: Blueprints call this module while they compile,
  # and an alias would make it depend on the contexts (a compile cycle).
  @keys [:languages, :admin_languages | Enum.map(~w(Images Videos Files), &Module.concat("Brando", &1))]

  @typedoc "A key under `:brando`, or a path into one (`[Brando.Images, :default_config]`)."
  @type path :: atom() | [atom(), ...]

  @doc "Reads `path` under `:brando` and records it for `track/1`."
  @spec read(path()) :: term()
  def read(path) do
    [key | _] = path = List.wrap(path)

    unless key in @keys do
      raise ArgumentError, "#{inspect(key)} is not configuration Brando checks at boot; add it to @keys"
    end

    Process.put(@reads, Enum.uniq([path | Process.get(@reads, [])]))

    # Through `RuntimeConfig`, as before: an asset's function config also
    # merges its default while the application runs
    case fetch([{key, Brando.RuntimeConfig.get(key)}], path) do
      {:ok, value} -> value
      :error -> nil
    end
  end

  @doc "Paths read so far while compiling the current file."
  @spec paths() :: [[atom(), ...]]
  def paths, do: Process.get(@reads, []) |> Enum.reverse()

  @doc """
  Reports every recorded path as compile-time configuration of the module
  compiling in `env`. Called in a module body.
  """
  @spec track(Macro.Env.t()) :: :ok
  def track(%Macro.Env{} = env) do
    Enum.each(paths(), &Application.compile_env(env, @app, &1, nil))
  end

  @doc """
  Raises when the running configuration differs from a value Brando was
  compiled with. `compile_env` is what Mix stored in Brando's `.app` file.
  """
  @spec check!(list()) :: :ok
  def check!(compile_env \\ compiled_env(), current \\ Application.get_all_env(@app)) do
    case stale(compile_env, current) do
      [] -> :ok
      stale -> raise ConfigError, message: message(stale)
    end
  end

  @doc "The checked paths whose compiled value differs from `current`."
  @spec stale(list(), keyword()) :: [{[atom(), ...], term(), term()}]
  def stale(compile_env, current) do
    for {@app, [key | _] = path, compiled} <- compile_env,
        key in @keys,
        (running = fetch(current, path)) != compiled,
        do: {path, compiled, running}
  end

  @doc """
  The compile-time values Mix stored in Brando's `.app` file. The application
  controller drops keys it does not know, so this reads the file, as Mix and
  releases do.
  """
  @spec compiled_env() :: list()
  def compiled_env do
    with dir when is_list(dir) <- :code.lib_dir(@app),
         {:ok, [{:application, @app, properties}]} <- :file.consult(Path.join([dir, "ebin", "#{@app}.app"])) do
      Keyword.get(properties, :compile_env, [])
    else
      _missing -> []
    end
  end

  # Access semantics, as `Application.compile_env/4` traverses a path.
  defp fetch(env, [key | path]) do
    Enum.reduce_while(path, Keyword.fetch(env, key), fn
      segment, {:ok, config} when is_list(config) or is_map(config) -> {:cont, Access.fetch(config, segment)}
      _segment, _result -> {:halt, :error}
    end)
  end

  defp message(stale) do
    entries =
      Enum.map_join(stale, "\n", fn {path, compiled, running} ->
        """
            #{config_line(path)}
              compiled: #{show(compiled)}
              running:  #{show(running)}
        """
      end)

    """


    Brando was compiled with different configuration than it runs with:

    #{entries}
    Brando reads these while compiling: the installation's languages become the
    values of every `language` field, and the default asset configs are merged
    into Blueprint assets. Set them in config/brando.exs (or another file
    config/config.exs imports), not in config/runtime.exs, then recompile Brando:

        mix deps.compile brando --force
    """
  end

  defp config_line([key]), do: "config :brando, #{inspect(key)}"
  defp config_line([key, option]), do: "config :brando, #{inspect(key)}, #{option}: …"
  defp config_line([key | rest]), do: "config :brando, #{inspect(key)} at #{inspect(rest)}"

  defp show({:ok, value}), do: inspect(value, limit: 20, printable_limit: 200)
  defp show(:error), do: "(not set)"
end
