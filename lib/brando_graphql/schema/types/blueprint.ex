defmodule BrandoGraphQL.Schema.Types.Blueprint do
  use BrandoWeb, :absinthe

  object :blueprint do
    field :source, :string
    field :application, :string
    field :domain, :string
    field :schema, :string
    field :modules, :blueprint_modules
  end

  object :blueprint_modules do
    field :schema, :string
    field :context, :string
    field :blueprint, :string
  end

  object :blueprint_queries do
    field :blueprint, type: :blueprint do
      arg :source, non_null(:string)

      resolve fn %{source: source}, _ ->
        source_module = Module.concat([source])
        {:ok, apply(source_module, :__blueprint__, [])}
      end
    end
  end
end
