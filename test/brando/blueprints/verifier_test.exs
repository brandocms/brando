defmodule Brando.Blueprint.VerifierTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO, only: [capture_io: 2]

  defmodule MediaItem do
    use Brando.Blueprint,
      application: "Brando",
      domain: "VerifierTest",
      schema: "MediaItem",
      singular: "media_item",
      plural: "media_items",
      gettext_module: Brando.Gettext

    attributes do
      attribute :title, :string
    end

    assets do
      asset :cover, :image, cfg: :default
      asset :video, :video, cfg: :default
      asset :document, :file, cfg: :default
    end
  end

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

  test "reports form inputs for unknown schema fields" do
    assert_form_error(
      quote do
        attributes do
          attribute :title, :string
        end

        forms do
          form do
            tab "Content" do
              fieldset do
                input :titel, :text
              end
            end
          end
        end
      end,
      ~r/references unknown schema field :titel/
    )
  end

  test "reports form options that reference unknown schema fields" do
    assert_form_error(
      quote do
        attributes do
          attribute :title, :string
          attribute :slug, :slug
        end

        forms do
          form do
            tab "Content" do
              fieldset do
                input :slug, :slug, source: :missing
              end
            end
          end
        end
      end,
      ~r/:source referencing unknown schema field :missing/
    )
  end

  test "reports inputs_for without a relation" do
    assert_form_error(
      quote do
        forms do
          form do
            tab "Content" do
              fieldset do
                inputs_for :items do
                  cardinality :many
                end
              end
            end
          end
        end
      end,
      ~r/must reference a declared relation/
    )
  end

  test "reports inputs_for cardinality that disagrees with its relation" do
    media_item = MediaItem

    assert_form_error(
      quote do
        relations do
          relation :items, :has_many, module: unquote(media_item)
        end

        forms do
          form do
            tab "Content" do
              fieldset do
                inputs_for :items
              end
            end
          end
        end
      end,
      ~r/cardinality :one for :has_many relation/
    )
  end

  test "reports unknown nested form fields" do
    media_item = MediaItem

    assert_form_error(
      quote do
        relations do
          relation :items, :has_many, module: unquote(media_item)
        end

        forms do
          form do
            tab "Content" do
              fieldset do
                inputs_for :items do
                  cardinality :many
                  input :caption, :text
                end
              end
            end
          end
        end
      end,
      ~r/unknown field :caption on .*MediaItem/
    )
  end

  test "reports invalid transformer asset fields" do
    media_item = MediaItem

    assert_form_error(
      quote do
        relations do
          relation :items, :has_many, module: unquote(media_item)
        end

        forms do
          form do
            tab "Content" do
              fieldset do
                inputs_for :items do
                  cardinality :many
                  style {:transformer, :missing}
                end
              end
            end
          end
        end
      end,
      ~r/unknown asset :missing/
    )
  end

  test "accepts a mixed-media transformer with valid related fields" do
    media_item = MediaItem

    module =
      compile_blueprint(
        quote do
          relations do
            relation :items, :has_many, module: unquote(media_item)
          end

          forms do
            form do
              tab "Content" do
                fieldset do
                  inputs_for :items do
                    cardinality :many
                    style {:transformer, [:cover, :video]}
                    default %{}

                    input :cover, :image
                    input :video, :video
                    input :title, :text
                  end
                end
              end
            end
          end
        end
      )

    assert %{style: {:transformer, [:cover, :video]}} =
             module.__form__().tabs |> hd() |> Map.fetch!(:fields) |> hd() |> Map.fetch!(:fields) |> hd()

    assert module.__form__().transformers == [{:items, [:cover, :video], %{}}]
  end

  defp assert_form_error(body, message_pattern) do
    capture_io(:stderr, fn -> Process.put(:compiled_invalid_blueprint, compile_blueprint(body)) end)
    module = Process.delete(:compiled_invalid_blueprint)

    assert {:error, error} = Brando.Blueprint.Forms.Verifier.verify(module.spark_dsl_config())
    assert Regex.match?(message_pattern, Exception.message(error))
    error
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

    module
  end
end
