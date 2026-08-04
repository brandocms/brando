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

  test "maps scalar and array enum declarations to their configured Ecto storage types" do
    module =
      compile_blueprint(
        quote do
          attributes do
            attribute :visibility, :enum, values: [public: "public", private: "private"], default: :private
            attribute :priority, Ecto.Enum, values: [low: 1, high: 2], default: :low
            attribute :formats, {:array, :enum}, values: [:jpg, :png], default: [:jpg]
          end
        end
      )

    assert module.__schema__(:type, :visibility) |> Ecto.Type.type() == :string
    assert module.__schema__(:type, :priority) |> Ecto.Type.type() == :integer
    assert module.__schema__(:type, :formats) |> Ecto.Type.type() == {:array, :string}
    assert Ecto.Enum.values(module, :formats) == [:jpg, :png]

    assert struct(module) |> Map.take([:visibility, :priority, :formats]) == %{
             visibility: :private,
             priority: :low,
             formats: [:jpg]
           }
  end

  test "keeps migration-only column options out of Ecto schema field options" do
    module =
      compile_blueprint(
        quote do
          attributes do
            attribute :amount, :decimal, null: false, precision: 12, scale: 4
          end

          relations do
            relation :owner, :belongs_to, module: unquote(MediaItem), null: false
          end
        end
      )

    assert module.__schema__(:type, :amount) == :decimal
    assert module.__schema__(:type, :owner_id) == :id
  end

  test "rejects malformed and misplaced attribute field options contextually" do
    invalid_declarations = [
      {quote(do: attribute(:title, :string, requried: true)), ~r/unsupported options \[:requried\]/},
      {quote(do: attribute(:title, :string, null: :no)), ~r/`:null` must be a boolean/},
      {quote(do: attribute(:title, :string, precision: 12)), ~r/only valid for decimal attributes/},
      {quote(do: attribute(:amount, :decimal, scale: 2)), ~r/`:scale` requires `:precision`/},
      {quote(do: attribute(:amount, :decimal, precision: 2, scale: 3)), ~r/exceeds `:precision`/},
      {quote(do: attribute(:status, :enum, values: [])), ~r/`:values` must be a non-empty/},
      {quote(do: attribute(:status, :enum, values: [:one, :one])), ~r/`:values` must be a non-empty/},
      {quote(do: attribute(:status, :enum, values: [one: 1, two: "2"])), ~r/`:values` must be a non-empty/},
      {quote(do: attribute(:status, :enum, values: [:one], embed_as: :atoms)), ~r/`:embed_as` must be/},
      {quote(do: attribute(:title, :string, values: [:one])), ~r/unsupported options \[:values\]/},
      {quote(do: attribute(:title, :string, writable: :sometimes)), ~r/`:writable` must be/},
      {quote(do: attribute(:inserted_at, :datetime, null: false)), ~r/timestamp attributes do not support/},
      {quote(do: attribute(:scratch, :string, virtual: true, null: false)), ~r/virtual attributes do not support/},
      {quote(do: attribute(:id, :integer, primary_key: true)), ~r/unsupported options \[:primary_key\]/}
    ]

    for {declaration, message} <- invalid_declarations do
      assert_raise Spark.Error.DslError, message, fn ->
        compile_blueprint(
          quote do
            attributes do
              unquote(declaration)
            end
          end
        )
      end
    end
  end

  test "rejects malformed language configuration before Ecto enum initialization" do
    assert_raise Spark.Error.DslError, ~r/language attribute `:languages` must be a list/, fn ->
      compile_blueprint(
        quote do
          attributes do
            attribute :language, :language, languages: [[value: "en"]]
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

  test "accepts cross-field constraints on attributes and assets" do
    # The verifier runs during compilation, so compiling at all is the assertion.
    module =
      compile_blueprint(
        quote do
          attributes do
            attribute :title, :string,
              constraints: [one_of: [:title, :subtitle], one_of_message: "need one"]

            attribute :subtitle, :string
          end

          assets do
            asset :cover, :image,
              constraints: [
                exactly_one_of: [:cover, :clip],
                check: [one_media_type: "image or video"]
              ],
              cfg: :default

            asset :clip, :video, cfg: :default
          end
        end
      )

    assert module.__schema__(:type, :cover_id) == :id
  end

  test "rejects a typo in an asset constraint at compile time" do
    # Assets were not run through constraint verification at all, so a typo
    # here used to survive compilation and raise from the changeset instead.
    assert_raise Spark.Error.DslError, ~r/unsupported options \[:one_off\]/, fn ->
      compile_blueprint(
        quote do
          assets do
            asset :cover, :image, constraints: [one_off: [:cover]], cfg: :default
          end
        end
      )
    end
  end

  test "rejects length constraints on assets, which have no length" do
    assert_raise Spark.Error.DslError, ~r/unsupported options \[:min_length\]/, fn ->
      compile_blueprint(
        quote do
          assets do
            asset :cover, :image, constraints: [min_length: 2], cfg: :default
          end
        end
      )
    end
  end

  test "rejects malformed constraint values" do
    assert_raise Spark.Error.DslError, ~r/unsupported value/, fn ->
      compile_blueprint(
        quote do
          attributes do
            attribute :title, :string, constraints: [one_of: "not a list"]
          end
        end
      )
    end

    assert_raise Spark.Error.DslError, ~r/unsupported value/, fn ->
      compile_blueprint(
        quote do
          attributes do
            attribute :title, :string, constraints: [check: [bad_message: :not_a_string]]
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

  test "only collision callbacks may combine persisted scopes and messages" do
    module =
      compile_blueprint(
        quote do
          attributes do
            attribute :language, :language

            attribute :slug, :slug,
              unique: [
                prevent_collision: fn _changeset -> __MODULE__ end,
                with: :language,
                message: "must be unique in this language"
              ]
          end
        end
      )

    assert %{opts: %{unique: unique_opts}} = Brando.Blueprint.Attributes.__attribute__(module, :slug)
    assert Keyword.get(unique_opts, :with) == :language
    assert is_function(Keyword.get(unique_opts, :prevent_collision), 1)

    assert_raise Spark.Error.DslError, ~r/can only be combined.*arity-one callback/, fn ->
      compile_blueprint(
        quote do
          attributes do
            attribute :slug, :slug, unique: [prevent_collision: true, message: "must be unique"]
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

    assert_raise Spark.Error.DslError, ~r/`:null` must be a boolean/, fn ->
      compile_blueprint(
        quote do
          relations do
            relation :owner, :belongs_to,
              module: unquote(media_item),
              null: :no
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

    assert_raise Spark.Error.DslError, ~r/`:unique` is only valid for :belongs_to, :many_to_many relations/, fn ->
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

  test "rejects unknown, misplaced, and ineffective relation options contextually" do
    media_item = MediaItem

    invalid_declarations = [
      {quote(do: relation(:items, :has_many, module: unquote(media_item), prelod_order: [:id])),
       ~r/unsupported options \[:prelod_order\]/},
      {quote(do: relation(:config, :embeds_one, module: unquote(media_item), cast: true)), ~r/`:cast` is only valid/},
      {quote(do: relation(:config, :embeds_one, module: unquote(media_item), sort_param: :sort_config)),
       ~r/`:sort_param` is only valid/},
      {quote(do: relation(:owner, :belongs_to, module: unquote(media_item), on_delete: :cascade)),
       ~r/`:on_delete` must be one of/},
      {quote(do: relation(:owner, :belongs_to, module: unquote(media_item), on_replace: :truncate)),
       ~r/`:on_replace` must be one of/},
      {quote(do: relation(:owner, :belongs_to, module: unquote(media_item), primary_key: :yes)),
       ~r/`:primary_key` must be a boolean/},
      {quote(do: relation(:items, :has_many, module: unquote(media_item), where: %{})),
       ~r/`:where` must be a keyword list/},
      {quote(
         do:
           relation(:items, :many_to_many,
             module: unquote(media_item),
             join_through: "owners_items",
             join_keys: [owner_id: :id]
           )
       ), ~r/`:join_keys` must contain exactly two/},
      {quote(
         do:
           relation(:items, :many_to_many,
             module: unquote(media_item),
             join_through: "owners_items",
             join_defaults: [active: true]
           )
       ), ~r/`:join_defaults` requires a schema module/},
      {quote(
         do:
           relation(:items, :many_to_many,
             module: unquote(media_item),
             join_through: "owners_items",
             unique: [with: :tenant_id]
           )
       ), ~r/`:unique` must be a boolean for many-to-many/},
      {quote(do: relation(:item, :has_one, module: unquote(media_item), required: true)),
       ~r/`:required` on :has_one requires `cast: true`/},
      {quote(
         do:
           relation(:items, :has_many,
             module: unquote(media_item),
             through: [:owner, :items],
             cast: true
           )
       ), ~r/`:through` relations cannot use `cast: true`/},
      {quote(
         do:
           relation(:items, :has_many,
             module: unquote(media_item),
             through: [:owner, :items],
             preload_order: [asc: :id]
           )
       ), ~r/`:through` relations do not support ignored Ecto options \[:preload_order\]/},
      {quote(do: relation(:items, :has_many, module: unquote(media_item), preload_order: [sideways: :id])),
       ~r/`:preload_order` must be/}
    ]

    for {declaration, message} <- invalid_declarations do
      assert_raise Spark.Error.DslError, message, fn ->
        compile_blueprint(
          quote do
            relations do
              unquote(declaration)
            end
          end
        )
      end
    end
  end

  test "supports has-one through associations without leaking Blueprint metadata to Ecto" do
    media_item = MediaItem

    module =
      compile_blueprint(
        quote do
          relations do
            relation :media_item, :belongs_to, module: unquote(media_item)

            relation :cover, :has_one,
              module: Brando.Images.Image,
              through: [:media_item, :cover]
          end
        end
      )

    association = module.__schema__(:association, :cover)
    assert association.__struct__ == Ecto.Association.HasThrough
    assert association.through == [:media_item, :cover]
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

  test "rejects define_field false without a persisted foreign-key field" do
    media_item = MediaItem

    assert_raise Spark.Error.DslError, ~r/no persisted field :owner_ref is declared/, fn ->
      compile_blueprint(
        quote do
          relations do
            relation :owner, :belongs_to,
              module: unquote(media_item),
              foreign_key: :owner_ref,
              define_field: false
          end
        end
      )
    end
  end

  test "requires manual foreign-key storage options on the declared attribute" do
    media_item = MediaItem

    assert_raise Spark.Error.DslError, ~r/configure \[:null, :source\] on foreign-key attribute :owner_ref/, fn ->
      compile_blueprint(
        quote do
          attributes do
            attribute :owner_ref, :id, source: :owner_column, null: false
          end

          relations do
            relation :owner, :belongs_to,
              module: unquote(media_item),
              foreign_key: :owner_ref,
              define_field: false,
              source: :owner_column,
              null: false
          end
        end
      )
    end
  end

  test "validates and preserves physical field sources" do
    media_item = MediaItem

    module =
      compile_blueprint(
        quote do
          attributes do
            attribute :title, :string, source: :headline
          end

          relations do
            relation :owner, :belongs_to, module: unquote(media_item), source: :owner_ref
            relation :metadata, :embeds_one, module: unquote(media_item), source: :payload
          end
        end
      )

    assert module.__schema__(:field_source, :title) == :headline
    assert module.__schema__(:field_source, :owner_id) == :owner_ref
    assert module.__schema__(:field_source, :metadata) == :payload

    assert_raise Spark.Error.DslError, ~r/`:source` must be an atom/, fn ->
      compile_blueprint(
        quote do
          attributes do
            attribute :title, :string, source: "headline"
          end
        end
      )
    end

    assert_raise Spark.Error.DslError, ~r/virtual attributes cannot declare a database `:source`/, fn ->
      compile_blueprint(
        quote do
          attributes do
            attribute :temporary, :string, virtual: true, source: :stored_temporary
          end
        end
      )
    end

    assert_raise Spark.Error.DslError, ~r/timestamp attributes do not support `:source`/, fn ->
      compile_blueprint(
        quote do
          attributes do
            attribute :inserted_at, :datetime, source: :created_at
          end
        end
      )
    end

    assert_raise Spark.Error.DslError, ~r/`:source` is only valid for/, fn ->
      compile_blueprint(
        quote do
          relations do
            relation :items, :has_many, module: unquote(media_item), source: :stored_items
          end
        end
      )
    end
  end

  test "rejects physical source collisions before Ecto schema generation" do
    assert_raise Spark.Error.DslError, ~r/duplicate database source "shared_column"/, fn ->
      compile_blueprint(
        quote do
          attributes do
            attribute :title, :string, source: :shared_column
            attribute :subtitle, :string, source: :shared_column
          end
        end
      )
    end

    shared_prefix = String.to_atom(String.duplicate("a", 63) <> "first")
    colliding_prefix = String.to_atom(String.duplicate("a", 63) <> "second")

    assert_raise Spark.Error.DslError, ~r/duplicate database source/, fn ->
      compile_blueprint(
        quote do
          attributes do
            attribute :title, :string, source: unquote(shared_prefix)
            attribute :subtitle, :string, source: unquote(colliding_prefix)
          end
        end
      )
    end

    assert_raise Spark.Error.DslError, ~r/duplicate database source "shared_primary_key"/, fn ->
      compile_blueprint(
        quote do
          primary_key {:id, :id, source: :shared_primary_key}

          attributes do
            attribute :title, :string, source: :shared_primary_key
          end
        end
      )
    end

    assert_raise Spark.Error.DslError, ~r/duplicate database source "inserted_at"/, fn ->
      compile_blueprint(
        quote do
          trait Brando.Trait.Timestamped

          attributes do
            attribute :created_by_import, :datetime, source: :inserted_at
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

  test "transformers default to offering an add entry button" do
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

                    input :cover, :image
                  end
                end
              end
            end
          end
        end
      )

    assert %{add_entry: true} = first_subform(module)
  end

  test "accepts a transformer that suppresses the add entry button" do
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
                    add_entry false

                    input :cover, :image
                  end
                end
              end
            end
          end
        end
      )

    assert %{add_entry: false} = first_subform(module)
    assert :ok = Brando.Blueprint.Forms.Verifier.verify(module.spark_dsl_config())
  end

  defp first_subform(module) do
    module.__form__().tabs
    |> hd()
    |> Map.fetch!(:fields)
    |> hd()
    |> Map.fetch!(:fields)
    |> hd()
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
