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

  test "rejects a bare array type before Ecto schema generation" do
    assert_raise Spark.Error.DslError, ~r/bare.*array.*invalid/i, fn ->
      compile_blueprint(
        quote do
          attributes do
            attribute :tags, :array
          end
        end
      )
    end
  end

  test "maps Blueprint UUID and timestamp attributes to valid Ecto types" do
    module =
      compile_blueprint(
        quote do
          attributes do
            attribute :external_id, :uuid
            attribute :published_at, :timestamp
          end
        end
      )

    assert module.__schema__(:type, :external_id) == Ecto.UUID
    assert module.__schema__(:type, :published_at) == :naive_datetime
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

  test "rejects non-boolean required and virtual options" do
    assert_raise Spark.Error.DslError, ~r/`:required` must be a boolean/, fn ->
      compile_blueprint(
        quote do
          attributes do
            attribute :title, :string, required: :yes
          end
        end
      )
    end

    assert_raise Spark.Error.DslError, ~r/`:virtual` must be a boolean/, fn ->
      compile_blueprint(
        quote do
          attributes do
            attribute :title, :string, virtual: :yes
          end
        end
      )
    end

    assert_raise Spark.Error.DslError, ~r/`:required` must be a boolean/, fn ->
      compile_blueprint(
        quote do
          assets do
            asset :cover, :image, cfg: :default, required: "yes"
          end
        end
      )
    end
  end

  test "rejects unsupported asset options instead of silently ignoring them" do
    assert_raise Spark.Error.DslError, ~r/unsupported options \[:requried\]/, fn ->
      compile_blueprint(
        quote do
          assets do
            asset :cover, :image, cfg: :default, requried: true
          end
        end
      )
    end

    assert_raise Spark.Error.DslError, ~r/unsupported options \[:on_replace\]/, fn ->
      compile_blueprint(
        quote do
          assets do
            asset :gallery, :gallery, cfg: :default, on_replace: :delete
          end
        end
      )
    end
  end

  test "rejects uniqueness scopes that are not persisted fields" do
    assert_raise Spark.Error.DslError, ~r/unknown persisted fields \[:missing\]/, fn ->
      compile_blueprint(
        quote do
          attributes do
            attribute :title, :string, unique: [with: :missing]
          end
        end
      )
    end

    assert_raise Spark.Error.DslError, ~r/unknown persisted fields \[:missing\]/, fn ->
      compile_blueprint(
        quote do
          attributes do
            attribute :slug, :slug, unique: [prevent_collision: :missing]
          end
        end
      )
    end
  end

  test "rejects uniqueness scopes that repeat persisted fields" do
    assert_raise Spark.Error.DslError, ~r/repeats persisted fields \[:title\]/, fn ->
      compile_blueprint(
        quote do
          attributes do
            attribute :title, :string, unique: [with: :title]
          end
        end
      )
    end

    assert_raise Spark.Error.DslError, ~r/repeats persisted fields \[:tenant_id\]/, fn ->
      compile_blueprint(
        quote do
          attributes do
            attribute :tenant_id, :integer
            attribute :title, :string, unique: [with: [:tenant_id, :tenant_id]]
          end
        end
      )
    end

    assert_raise Spark.Error.DslError, ~r/repeats persisted fields \[:slug\]/, fn ->
      compile_blueprint(
        quote do
          attributes do
            attribute :slug, :slug, unique: [prevent_collision: :slug]
          end
        end
      )
    end

    assert_raise Spark.Error.DslError, ~r/repeats persisted fields \[:location_ref\]/, fn ->
      compile_blueprint(
        quote do
          relations do
            relation :location, :belongs_to,
              module: Brando.BlueprintTest.P1.Location,
              foreign_key: :location_ref,
              unique: [with: :location_ref]
          end
        end
      )
    end
  end

  test "rejects uniqueness configurations that cannot be enforced" do
    assert_raise Spark.Error.DslError, ~r/virtual attributes cannot be unique/, fn ->
      compile_blueprint(
        quote do
          attributes do
            attribute :temporary, :string, virtual: true, unique: true
          end
        end
      )
    end

    assert_raise Spark.Error.DslError, ~r/arity-one function/, fn ->
      compile_blueprint(
        quote do
          attributes do
            attribute :slug, :slug, unique: [prevent_collision: fn -> :invalid end]
          end
        end
      )
    end

    assert_raise Spark.Error.DslError, ~r/`prevent_collision` requires a string/, fn ->
      compile_blueprint(
        quote do
          attributes do
            attribute :position, :integer, unique: [prevent_collision: true]
          end
        end
      )
    end
  end

  test "rejects fields that collide with the implicit primary key" do
    assert_raise Spark.Error.DslError, ~r/duplicate Ecto field :id/, fn ->
      compile_blueprint(
        quote do
          attributes do
            attribute :id, :integer
          end
        end
      )
    end
  end

  test "validates relation storage options before Ecto schema generation" do
    media_item = MediaItem

    assert_raise Spark.Error.DslError, ~r/`:module` must be a module atom/, fn ->
      compile_blueprint(
        quote do
          relations do
            relation :owner, :belongs_to, module: nil
          end
        end
      )
    end

    assert_raise Spark.Error.DslError, ~r/`:required` must be a boolean/, fn ->
      compile_blueprint(
        quote do
          relations do
            relation :owner, :belongs_to,
              module: unquote(media_item),
              required: :yes
          end
        end
      )
    end

    assert_raise Spark.Error.DslError, ~r/`:foreign_key` must be an atom/, fn ->
      compile_blueprint(
        quote do
          relations do
            relation :owner, :belongs_to,
              module: unquote(media_item),
              foreign_key: "owner_id"
          end
        end
      )
    end

    assert_raise Spark.Error.DslError, ~r/`:through` must be a non-empty atom list/, fn ->
      compile_blueprint(
        quote do
          relations do
            relation :items, :has_many,
              module: unquote(media_item),
              through: []
          end
        end
      )
    end

    assert_raise Spark.Error.DslError, ~r/`:join_through` is only valid for :many_to_many relations/, fn ->
      compile_blueprint(
        quote do
          relations do
            relation :items, :has_many,
              module: unquote(media_item),
              join_through: "items_join"
          end
        end
      )
    end

    assert_raise Spark.Error.DslError, ~r/only belongs-to relations can be unique/, fn ->
      compile_blueprint(
        quote do
          relations do
            relation :items, :has_many,
              module: unquote(media_item),
              unique: true
          end
        end
      )
    end

    assert_raise Spark.Error.DslError, ~r/constraint :min_length has an unsupported value/, fn ->
      compile_blueprint(
        quote do
          relations do
            relation :owner, :belongs_to,
              module: unquote(media_item),
              constraints: [min_length: 1]
          end
        end
      )
    end
  end

  test "supports manually declared custom foreign-key fields" do
    media_item = MediaItem

    module =
      compile_blueprint(
        quote do
          attributes do
            attribute :owner_ref, :id
          end

          relations do
            relation :owner, :belongs_to,
              module: unquote(media_item),
              foreign_key: :owner_ref,
              define_field: false,
              required: true
          end
        end
      )

    assert Enum.count(module.__schema__(:fields), &(&1 == :owner_ref)) == 1
    assert module.__schema__(:association, :owner).owner_key == :owner_ref
    assert module.__castable_relations__() == [:owner_ref]
    assert module.__required_relations__() == [:owner_ref]
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

  test "reports static form queries with invalid matches" do
    assert_form_error(
      quote do
        forms do
          form do
            query %{matches: :invalid}
          end
        end
      end,
      ~r/static query :matches must be a map/
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
