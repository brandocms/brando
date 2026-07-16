defmodule Brando.Blueprint.VerifierTest do
  use ExUnit.Case, async: false

  test "rejects malformed unique options at compile time" do
    assert_raise Spark.Error.DslError, ~r/`:unique` must be a boolean or keyword list/, fn ->
      compile_blueprint(
        quote do
          attributes do
            attribute :title, :string, unique: "yes"
          end
        end
      )
    end
  end

  test "rejects unsupported constraints at compile time" do
    assert_raise Spark.Error.DslError, ~r/unsupported options \[:minimum\]/, fn ->
      compile_blueprint(
        quote do
          attributes do
            attribute :title, :string, constraints: [minimum: 2]
          end
        end
      )
    end
  end

  test "rejects cast callbacks the changeset runner cannot execute" do
    assert_raise Spark.Error.DslError, ~r/unsupported `:cast` option/, fn ->
      compile_blueprint(
        quote do
          relations do
            relation :location, :belongs_to,
              module: Brando.BlueprintTest.P1.Location,
              cast: [using: {Brando.BlueprintTest.P1.Location, :changeset}]
          end
        end
      )
    end
  end

  test "rejects ambiguous rename declarations" do
    assert_raise Spark.Error.DslError, ~r/points at declared attribute :old_title/, fn ->
      compile_blueprint(
        quote do
          attributes do
            attribute :old_title, :string
            attribute :title, :string, rename_from: :old_title
          end
        end
      )
    end
  end

  defp compile_blueprint(body) do
    unique = System.unique_integer([:positive])
    module = Module.concat(__MODULE__, "Invalid#{unique}")
    schema = "Invalid#{unique}"

    Code.compile_quoted(
      quote do
        defmodule unquote(module) do
          use Brando.Blueprint,
            application: "Brando",
            domain: "VerifierTest",
            schema: unquote(schema),
            singular: "invalid",
            plural: "invalids",
            gettext_module: Brando.Gettext

          unquote(body)
        end
      end
    )
  end
end
