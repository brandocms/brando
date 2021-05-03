defmodule BrandoGraphQL.Schema.Types.Common do
  use BrandoWeb, :absinthe

  object :status_entry do
    field :id, :id
    field :status, :string
  end

  object :common_mutations do
    field :update_entry_status, type: :status_entry do
      arg :id, non_null(:id)
      arg :schema, non_null(:string)
      arg :status, non_null(:string)

      resolve fn %{"id" => id, "schema" => schema_binary, "status" => status}, _ ->
        schema_module = Module.concat([schema_binary])
        context = Brando.Schema.get_context_for(schema_module)
        singular = Brando.Schema.get_singular_for(schema_module)
        apply(context, :"update_#{singular}", [id, %{status: status}])
      end
    end
  end
end
