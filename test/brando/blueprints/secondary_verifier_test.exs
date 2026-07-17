defmodule Brando.Blueprint.SecondaryVerifierTest do
  use ExUnit.Case, async: false

  defmodule JSONLDRoot do
    defstruct "@type": "Thing",
              "@id": nil,
              name: nil,
              nested: nil,
              nested_items: nil,
              url: nil
  end

  defmodule JSONLDNested do
    defstruct [:name]

    def build(data), do: struct(__MODULE__, data)
  end

  def datasource_list(module, language, vars, configured) do
    {:ok, {module, language, vars, configured}}
  end

  def datasource_get(identifier, configured), do: {:ok, {identifier, configured}}

  test "executes datasource MFA callbacks with runtime arguments followed by configured arguments" do
    callback_module = __MODULE__

    module =
      compile_blueprint(
        quote do
          datasources do
            datasource :all do
              type :list
              list {unquote(callback_module), :datasource_list, [:configured]}
            end

            datasource :one do
              type :single
              get {unquote(callback_module), :datasource_get, [:configured]}
            end
          end
        end
      )

    assert Brando.Datasource.list_results(module, :all, %{draft: true}, "en") ==
             {:ok, {module, "en", %{draft: true}, :configured}}

    assert Brando.Datasource.get_single(module, :one, 123) == {:ok, {123, :configured}}
  end

  test "requires the callbacks used by each datasource type" do
    assert_compile_error(
      ~r/`:list` datasource requires a `list` callback/,
      quote do
        datasources do
          datasource :missing_list do
            type :list
          end
        end
      end
    )

    assert_compile_error(
      ~r/`:selection` datasource requires a `get` callback/,
      quote do
        datasources do
          datasource :missing_get do
            type :selection
            list fn _, _, _ -> {:ok, []} end
          end
        end
      end
    )

    assert_compile_error(
      ~r/`:single` datasource requires a `get` callback/,
      quote do
        datasources do
          datasource :missing_get do
            type :single
          end
        end
      end
    )
  end

  test "rejects ambiguous datasource and datasource-meta keys" do
    assert_compile_error(
      ~r/datasource :duplicate is declared more than once/,
      quote do
        datasources do
          datasource :duplicate do
            type :list
            list fn _, _, _ -> {:ok, []} end
          end

          datasource :duplicate do
            type :list
            list fn _, _, _ -> {:ok, []} end
          end
        end
      end
    )

    assert_compile_error(
      ~r/declares meta key :caption more than once/,
      quote do
        datasources do
          datasource :entries do
            type :selection
            list fn _, _, _ -> {:ok, []} end
            get fn identifiers -> {:ok, identifiers} end
            meta :caption, :text, label: "Caption"
            meta :caption, :textarea, label: "Long caption"
          end
        end
      end
    )
  end

  test "validates the singular metadata schema and its targets" do
    assert_compile_error(
      ~r/only one `meta_schema` can be declared/,
      quote do
        meta_schema do
          field "title", & &1.title
        end

        meta_schema do
          field "description", & &1.description
        end
      end
    )

    assert_compile_error(
      ~r/meta field targets must be a non-empty string/,
      quote do
        meta_schema do
          field [], & &1.title
        end
      end
    )
  end

  test "validates JSON-LD schemas, fields, types, and callback requirements" do
    root = JSONLDRoot

    assert_compile_error(
      ~r/only one `json_ld_schema` can be declared/,
      quote do
        json_ld_schema unquote(root) do
          field :name, :string, & &1.name
        end

        json_ld_schema MapSet do
        end
      end
    )

    assert_compile_error(
      ~r/field :missing does not exist/,
      quote do
        json_ld_schema unquote(root) do
          field :missing, :string, & &1.name
        end
      end
    )

    assert_compile_error(
      ~r/type :string requires a value callback/,
      quote do
        json_ld_schema unquote(root) do
          field :name, :string
        end
      end
    )

    assert_compile_error(
      ~r/type :current_url derives its value and does not accept a callback/,
      quote do
        json_ld_schema unquote(root) do
          field :url, :current_url, & &1.url
        end
      end
    )

    assert_compile_error(
      ~r/must be an available module exporting `build\/1`/,
      quote do
        json_ld_schema unquote(root) do
          field :nested, URI, & &1.nested
        end
      end
    )
  end

  test "extracts a validated JSON-LD schema with scalar, nested, list, and derived fields" do
    root = JSONLDRoot
    nested = JSONLDNested

    module =
      compile_blueprint(
        quote do
          json_ld_schema unquote(root) do
            field :name, :string, & &1.name
            field :nested, unquote(nested), & &1.nested
            field :nested_items, {:list, unquote(nested)}, & &1.nested_items
            field :url, :current_url
          end
        end
      )

    data = %{
      name: "Root",
      nested: %{name: "One"},
      nested_items: [%{name: "Two"}],
      __meta__: %{current_url: "https://example.com/entry"}
    }

    assert Brando.JSONLD.extract_json_ld(module, data) == %JSONLDRoot{
             "@type": "Thing",
             "@id": "https://example.com/entry/#thing",
             name: "Root",
             nested: %JSONLDNested{name: "One"},
             nested_items: [%JSONLDNested{name: "Two"}],
             url: "https://example.com/entry"
           }
  end

  test "validates listing declarations consumed by the admin list runtime" do
    assert_compile_error(
      ~r/listing limit must be zero or a positive integer/,
      quote do
        listings do
          listing do
            limit -1
          end
        end
      end
    )

    assert_compile_error(
      ~r/listing query `:filter` must be a map/,
      quote do
        listings do
          listing do
            query %{filter: :invalid}
          end
        end
      end
    )

    assert_compile_error(
      ~r/declares duplicate filter "title"/,
      quote do
        listings do
          listing do
            filter label: "Title", key: "title"
            filter label: "Again", key: "title"
          end
        end
      end
    )

    assert_compile_error(
      ~r/select filters require static options/,
      quote do
        listings do
          listing do
            filter label: "Status", key: "status", type: :select
          end
        end
      end
    )

    assert_compile_error(
      ~r/sort order must be a non-empty order string/,
      quote do
        listings do
          listing do
            sort :broken, label: "Broken", order: "sideways title"
          end
        end
      end
    )

    assert_compile_error(
      ~r/actions require a non-empty event/,
      quote do
        listings do
          listing do
            action label: "Broken"
          end
        end
      end
    )

    assert_compile_error(
      ~r/child listing references undeclared listing :children/,
      quote do
        listings do
          listing do
            child_listing name: :children, schema: unquote(__MODULE__)
          end
        end
      end
    )

    assert_compile_error(
      ~r/only `:csv` is implemented/,
      quote do
        listings do
          listing do
            export :entries, label: "Entries", type: :xlsx, fields: [:id]
          end
        end
      end
    )
  end

  test "accepts a complete select filter and child-listing graph" do
    module =
      compile_blueprint(
        quote do
          listings do
            listing do
              filter do
                label "Status"
                key("status")
                type :select
                default "published"
                option("All", nil)
                option("Published", "published")
              end

              child_listing name: :children, schema: unquote(__MODULE__)
            end

            listing :children do
              sort :newest, label: "Newest", order: [desc: :inserted_at]
              action label: "Edit", event: "edit_entry"
              default_actions false
            end
          end
        end
      )

    assert [%{filters: [%{key: "status", type: :select}], child_listings: [%{name: :children}]} | _] =
             Spark.Dsl.Extension.get_entities(module, [:listings])

    listing = module |> Spark.Dsl.Extension.get_entities([:listings]) |> List.first()

    assert Brando.Blueprint.Listings.merge_filter_defaults(%{filter: %{language: "en"}}, listing) == %{
             filter: %{language: "en", status: "published"}
           }

    assert Brando.Blueprint.Listings.merge_filter_defaults(%{filter: %{status: "draft"}}, listing) == %{
             filter: %{status: "draft"}
           }

    assert Brando.Blueprint.Listings.merge_filter_defaults(%{}, %{
             filters: [%{key: "full_case", default: false}]
           }) == %{}
  end

  test "JSON-LD helpers preserve absent optional values and schemas" do
    assert Brando.JSONLD.extract_json_ld(Brando.BlueprintTest.Project, %{}) == nil
    assert Brando.JSONLD.to_date(nil) == nil
    assert Brando.JSONLD.to_datetime(nil) == nil
  end

  test "rejects duplicate translation contexts and keys before map conversion" do
    assert_compile_error(
      ~r/translation context :naming is declared more than once/,
      quote do
        translations do
          context :naming do
            translate :singular, "entry"
          end

          context :naming do
            translate :plural, "entries"
          end
        end
      end
    )

    assert_compile_error(
      ~r/translation key :singular is declared more than once/,
      quote do
        translations do
          context :naming do
            translate :singular, "entry"
            translate :singular, "record"
          end
        end
      end
    )
  end

  defp assert_compile_error(pattern, body) do
    assert_raise Spark.Error.DslError, pattern, fn -> compile_blueprint(body) end
  end

  defp compile_blueprint(body) do
    unique = System.unique_integer([:positive])
    module = Module.concat(__MODULE__, "Dynamic#{unique}")
    schema = "Dynamic#{unique}"

    Code.compile_quoted(
      quote do
        defmodule unquote(module) do
          use Brando.Blueprint,
            application: "Brando",
            domain: "SecondaryVerifierTest",
            schema: unquote(schema),
            singular: "dynamic",
            plural: "dynamics",
            gettext_module: Brando.Gettext

          unquote(body)
        end
      end
    )

    module
  end
end
