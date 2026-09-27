defmodule Brando.Blueprint.ListingSelectFilterTest do
  use ExUnit.Case, async: true

  defp compile(name, filter_ast) do
    module = Module.concat(__MODULE__, name)

    Code.compile_quoted(
      quote do
        defmodule unquote(module) do
          use Brando.Blueprint,
            application: "Brando",
            domain: "SelectFilterTest",
            schema: unquote(to_string(name)),
            singular: "item",
            plural: "items",
            gettext_module: Brando.Gettext

          attributes do
            attribute :category, :string
          end

          listings do
            listing do
              unquote(filter_ast)
            end
          end

          def category_options(_), do: [{"Books", "book"}]
        end
      end
    )

    [listing] = Spark.Dsl.Extension.get_entities(module, [:listings])
    [filter] = listing.filters
    filter
  end

  test "options as a block, all settings inside it" do
    filter =
      compile(
        :InBlock,
        quote do
          filter do
            label "Category"
            key("category")
            type :select
            option("Books", "book")
          end
        end
      )

    assert [%{label: "Books", value: "book"}] = filter.options
  end

  test "options as a block after keyword settings" do
    filter =
      compile(
        :KeywordAndBlock,
        quote do
          filter label: "Category", key: "category", type: :select do
            option("Books", "book")
          end
        end
      )

    assert [%{label: "Books", value: "book"}] = filter.options
  end

  test "options from a callback" do
    filter =
      compile(
        :Callback,
        quote do
          filter label: "Category", key: "category", type: :select, options: &__MODULE__.category_options/1
        end
      )

    assert is_function(filter.options, 1)
    assert filter.options.(%{}) == [{"Books", "book"}]
  end
end
