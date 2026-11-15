defmodule Brando.Blueprint.CompileConfig do
  @moduledoc false

  # The installation's languages, which a Blueprint compiles into the values of
  # its `language` fields. A plain read is invisible to Mix, so a Brando
  # installed from Hex or Git would keep the old values after a config change.
  #
  # `read/1` reads a list and records the key for the file being compiled (each
  # file compiles in its own process). `track/1` runs at the end of each
  # Blueprint and reports the recorded keys through `Application.compile_env/4`,
  # so Mix stores the values used and recompiles what read a changed one,
  # dependencies included.
  #
  # `config/runtime.exs` is read after compilation. A release whose runtime
  # value differs from the compiled one refuses to boot with Elixir's message;
  # Mix does not check a dependency's compile env, so `check!/0` (from
  # `Brando.System`) compares the language codes.

  alias Brando.Exception.ConfigError

  @app :brando
  @keys [:languages, :admin_languages]
  @reads {__MODULE__, :reads}
  @default_languages [
    [value: "en", text: "English"],
    [value: "no", text: "Norsk"]
  ]

  @doc "Reads `key` under `:brando` and records it for `track/1`."
  @spec read(:languages | :admin_languages) :: list() | nil
  def read(key) when key in @keys do
    Process.put(@reads, Enum.uniq([key | Process.get(@reads, [])]))
    Brando.RuntimeConfig.get(key)
  end

  @doc "The installation's languages, or Brando's default when none are configured."
  @spec languages() :: list()
  def languages, do: read(:languages) || @default_languages

  @doc "Keys read so far while compiling the current file."
  @spec keys() :: [atom()]
  def keys, do: Process.get(@reads, []) |> Enum.reverse()

  @doc "Reports every recorded key as compile-time configuration of the module compiling in `env`."
  @spec track(Macro.Env.t()) :: :ok
  def track(%Macro.Env{} = env) do
    Enum.each(keys(), &Application.compile_env(env, @app, &1, nil))
  end

  @doc """
  Raises when the configured language codes differ from those Brando was
  compiled with. Labels and order are not compared. `compile_env` is what Mix
  stored in Brando's `.app` file.
  """
  @spec check!(list(), keyword()) :: :ok
  def check!(compile_env \\ compiled_env(), current \\ Application.get_all_env(@app)) do
    compiled = for {@app, [key], {:ok, value}} <- compile_env, key in @keys, do: {key, value}
    checked = for {@app, [key], _return} <- compile_env, key in @keys, uniq: true, do: key

    case Enum.reject(Enum.map(checked, &diff(&1, compiled, current)), &is_nil/1) do
      [] -> :ok
      diffs -> raise ConfigError, message: message(diffs)
    end
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

  defp diff(key, compiled, current) do
    compiled_codes = codes(key, compiled)
    current_codes = codes(key, current)

    if compiled_codes != current_codes do
      {key, MapSet.difference(compiled_codes, current_codes), MapSet.difference(current_codes, compiled_codes)}
    end
  end

  # The codes a `language` field compiled from `env` accepts: an unset
  # `admin_languages` falls back to `languages`, an unset `languages` to
  # Brando's default
  defp codes(:admin_languages, env) do
    case env[:admin_languages] do
      nil -> codes(:languages, env)
      languages -> codes_of(languages)
    end
  end

  defp codes(:languages, env), do: codes_of(env[:languages] || @default_languages)

  defp codes_of(languages), do: MapSet.new(languages, &to_string(&1[:value]))

  defp message(diffs) do
    entries =
      Enum.map_join(diffs, "\n", fn {key, compiled_only, configured_only} ->
        """
            config :brando, #{inspect(key)}
              compiled, not configured: #{list(compiled_only)}
              configured, not compiled: #{list(configured_only)}
        """
      end)

    """


    Brando was compiled with other languages than it runs with:

    #{entries}
    A `language` field accepts the codes configured when Brando was compiled.
    Set these keys in compile-time config, config/brando.exs or
    config/config.exs (not config/runtime.exs, which is read after
    compilation), then recompile Brando:

        mix deps.compile brando --force
    """
  end

  defp list(codes) do
    case Enum.sort(codes) do
      [] -> "(none)"
      codes -> Enum.join(codes, ", ")
    end
  end
end
