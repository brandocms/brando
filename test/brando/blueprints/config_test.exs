defmodule Brando.Blueprint.ConfigTest do
  use ExUnit.Case, async: false

  alias Brando.Exception.BlueprintError

  @valid_options [
    application: "Brando",
    domain: "BlueprintConfigTest",
    schema: "Record",
    singular: "record",
    plural: "records",
    gettext_module: Brando.Gettext
  ]

  test "accepts valid root and body configuration" do
    module =
      compile_blueprint(
        @valid_options,
        quote do
          table "blueprint_config_records"
          primary_key :uuid
          factory %{title: "Factory title"}
        end
      )

    assert module.__naming__().table_name == "blueprint_config_records"
    assert module.__primary_key__() == {:id, :binary_id, autogenerate: true}
    assert module.__schema__(:type, :id) == :binary_id
    assert module.__factory__(%{status: :draft}) == %{status: :draft, title: "Factory title"}
  end

  test "rejects missing, unknown, and duplicate use options contextually" do
    assert_raise BlueprintError, ~r/missing required options: \[:plural\]/, fn ->
      compile_blueprint(Keyword.delete(@valid_options, :plural))
    end

    assert_raise BlueprintError, ~r/unknown options: \[:singluar\]/, fn ->
      compile_blueprint([{:singluar, "record"} | @valid_options])
    end

    assert_raise BlueprintError, ~r/duplicate options: \[:application\]/, fn ->
      compile_blueprint([{:application, "Duplicate"} | @valid_options])
    end
  end

  test "rejects malformed use option values before macro setup" do
    invalid_options = [
      {:application, :brando, ~r/`:application` must be a PascalCase module segment string/},
      {:domain, "content", ~r/`:domain` must be a PascalCase module segment/},
      {:singular, "Record", ~r/`:singular` must be a snake_case identifier/},
      {:router_scope, true, ~r/`:router_scope` must be nil, an atom, or a snake_case string/},
      {:gettext_module, "Brando.Gettext", ~r/`:gettext_module` must be a module atom or nil/},
      {:extensions, [nil], ~r/`:extensions` must contain only module atoms/}
    ]

    Enum.each(invalid_options, fn {name, value, message} ->
      assert_raise BlueprintError, message, fn ->
        compile_blueprint(Keyword.put(@valid_options, name, value))
      end
    end)
  end

  test "rejects invalid evaluated body settings in the semantic verifier" do
    invalid_settings = [
      {quote(do: data_layer(:memory)), ~r/`:data_layer` must be `:database` or `:embedded`/},
      {quote(do: table("Invalid-Table")), ~r/`:table_name` must be a snake_case identifier/},
      {quote(do: primary_key(:serial)), ~r/`:primary_key` must use the default/},
      {quote(do: primary_key({:uuid, Ecto.UUID, autogenerate: true})), ~r/`:primary_key` must use the default/},
      {quote(do: primary_key({:id, :id, source: "record_pk"})), ~r/`:primary_key` source must be an atom/},
      {quote(do: factory(title: "invalid")), ~r/`:factory` must be a plain map/},
      {quote(do: factory(%URI{})), ~r/`:factory` must be a plain map/},
      {quote(do: @allow_mark_as_deleted(:sometimes)), ~r/`:allow_mark_as_deleted` must be a boolean/},
      {quote(do: singular("Invalid")), ~r/`:singular` must be a snake_case identifier/}
    ]

    Enum.each(invalid_settings, fn {body, message} ->
      assert_raise Spark.Error.DslError, message, fn ->
        compile_blueprint(@valid_options, body)
      end
    end)
  end

  defp compile_blueprint(options, body \\ quote(do: nil)) do
    module = unique_module("Record")

    Code.compile_quoted(
      quote do
        defmodule unquote(module) do
          use Brando.Blueprint, unquote(options)

          identifier false
          persist_identifier false

          unquote(body)
        end
      end
    )

    module
  end

  defp unique_module(name) do
    Module.concat(__MODULE__, "#{name}#{System.unique_integer([:positive])}")
  end
end
