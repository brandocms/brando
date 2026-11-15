defmodule Brando.Blueprint.CompileConfigTest do
  # Sets the global compiler tracers while it compiles Blueprints
  use ExUnit.Case, async: false

  alias Brando.Blueprint.CompileConfig
  alias Brando.Exception.ConfigError

  defmodule Tracer do
    @moduledoc false
    def trace({:compile_env, :brando, path, return}, env) do
      send(:persistent_term.get(Brando.Blueprint.CompileConfigTest), {:compile_env, env.module, path, return})
      :ok
    end

    def trace(_event, _env), do: :ok
  end

  setup do
    :persistent_term.put(__MODULE__, self())
    tracers = Code.get_compiler_option(:tracers)
    Code.put_compiler_option(:tracers, [Tracer | tracers])

    on_exit(fn ->
      Code.put_compiler_option(:tracers, tracers)
      :persistent_term.erase(__MODULE__)
    end)
  end

  # Each file compiles in a process of its own, which `read/1` records in
  defp compile(module, body) do
    Task.async(fn ->
      Code.compile_quoted(
        quote do
          defmodule unquote(module) do
            use Brando.Blueprint,
              application: "Brando",
              domain: "CompileConfigTest",
              schema: "Entry",
              singular: "entry",
              plural: "entries",
              gettext_module: Brando.Gettext

            unquote(body)
          end
        end
      )
    end)
    |> Task.await(30_000)
  end

  defp tracked(module) do
    receive do
      {:compile_env, ^module, path, return} -> [{path, return} | tracked(module)]
    after
      0 -> []
    end
  end

  test "a language field reports the installation's languages to Mix" do
    module = Module.concat(__MODULE__, Language)

    compile(module, quote(do: attributes(do: attribute(:language, :language))))

    languages = Application.fetch_env!(:brando, :languages)
    assert {[:languages], {:ok, languages}} in tracked(module)
    assert Ecto.Enum.values(module, :language) == Enum.map(languages, &String.to_atom(&1[:value]))
  end

  test "a language field with its own list, and an asset with its own config struct, report nothing" do
    module = Module.concat(__MODULE__, Untracked)

    compile(
      module,
      quote do
        attributes do
          attribute :language, :language, languages: [[value: "sv", text: "Svenska"]]
        end
      end
    )

    assert tracked(module) == []
  end

  test "an asset merged over the default config reports that default" do
    module = Module.concat(__MODULE__, Asset)

    compile(module, quote(do: assets(do: asset(:cover, :image, cfg: %{upload_path: "images/cover"}))))

    default_config = Application.fetch_env!(:brando, Brando.Images)[:default_config]
    assert tracked(module) == [{[Brando.Images, :default_config], {:ok, default_config}}]
  end

  test "Brando's own Blueprints record the values in its application file" do
    paths = for {:brando, path, _return} <- CompileConfig.compiled_env(), do: path

    for path <- [[:languages], [:admin_languages], [Brando.Images, :default_config]] do
      assert path in paths
    end
  end

  test "read/1 refuses a key the boot check does not cover" do
    assert_raise ArgumentError, ~r/:media_path is not configuration Brando checks at boot/, fn ->
      CompileConfig.read(:media_path)
    end
  end

  describe "check!/2" do
    @english [[value: "en", text: "English"]]
    @norwegian [[value: "en", text: "English"], [value: "no", text: "Norsk"]]

    test "passes when the running values are the compiled ones" do
      compile_env = [{:brando, [:languages], {:ok, @english}}, {:brando, [Brando.Images, :default_config], :error}]

      assert CompileConfig.check!(compile_env, languages: @english, "Elixir.Brando.Images": [processor_module: X]) ==
               :ok
    end

    test "ignores compile-time values it does not own" do
      assert CompileConfig.check!([{:brando, [:env], {:ok, :dev}}, {:acme, [:languages], {:ok, []}}], env: :prod) ==
               :ok
    end

    test "names the key, both values and the command when a value changed after compilation" do
      error =
        assert_raise ConfigError, fn ->
          CompileConfig.check!([{:brando, [:languages], {:ok, @english}}], languages: @norwegian)
        end

      assert error.message =~ "config :brando, :languages\n"
      assert error.message =~ ~s(compiled: [[value: "en", text: "English"]])
      assert error.message =~ ~s(running:  [[value: "en", text: "English"], [value: "no", text: "Norsk"]])
      assert error.message =~ "not in config/runtime.exs"
      assert error.message =~ "mix deps.compile brando --force"
    end

    test "reports a nested option, and a value set only at runtime" do
      error =
        assert_raise ConfigError, fn ->
          CompileConfig.check!(
            [{:brando, [Brando.Images, :default_config], :error}],
            "Elixir.Brando.Images": [default_config: %{sizes: :standard}]
          )
        end

      assert error.message =~ "config :brando, Brando.Images, default_config: …"
      assert error.message =~ "compiled: (not set)"
    end
  end
end
