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

  test "a language field with its own list reports nothing" do
    module = Module.concat(__MODULE__, OwnList)

    compile(
      module,
      quote(do: attributes(do: attribute(:language, :language, languages: [[value: "sv", text: "Svenska"]])))
    )

    assert tracked(module) == []
    assert Ecto.Enum.values(module, :language) == [:sv]
  end

  test "Brando's own Blueprints record the languages in its application file" do
    paths = for {:brando, path, _return} <- CompileConfig.compiled_env(), do: path

    assert [:languages] in paths
    assert [:admin_languages] in paths
  end

  describe "check!/2" do
    @english [[value: "en", text: "English"]]
    @norwegian [[value: "en", text: "English"], [value: "no", text: "Norsk"]]

    test "passes when the codes are the compiled ones, whatever their labels and order" do
      compile_env = [{:brando, [:languages], {:ok, @norwegian}}, {:brando, [:admin_languages], {:ok, @english}}]

      assert CompileConfig.check!(compile_env,
               languages: [[value: "no", text: "Norwegian"], [value: "en", text: "Engelsk"]],
               admin_languages: [[value: "en", text: "Engelsk"]]
             ) == :ok
    end

    test "compares an unset list as the list it falls back to" do
      compile_env = [{:brando, [:languages], :error}, {:brando, [:admin_languages], :error}]

      assert CompileConfig.check!(compile_env, languages: @norwegian) == :ok
      assert CompileConfig.check!(compile_env, languages: @norwegian, admin_languages: @norwegian) == :ok
      assert_raise ConfigError, fn -> CompileConfig.check!(compile_env, languages: @english) end
    end

    test "ignores compile-time values it does not own" do
      assert CompileConfig.check!([{:brando, [:env], {:ok, :dev}}, {:acme, [:languages], {:ok, []}}], env: :prod) ==
               :ok
    end

    test "names the key, the codes that differ and the command" do
      error =
        assert_raise ConfigError, fn ->
          CompileConfig.check!(
            [{:brando, [:languages], {:ok, @norwegian}}],
            languages: [[value: "en", text: "English"], [value: "sv", text: "Svenska"]]
          )
        end

      assert error.message =~ "config :brando, :languages\n"
      assert error.message =~ "compiled, not configured: no\n"
      assert error.message =~ "configured, not compiled: sv\n"
      refute error.message =~ "English"
      assert error.message =~ "not config/runtime.exs"
      assert error.message =~ "mix deps.compile brando --force"
    end
  end
end
