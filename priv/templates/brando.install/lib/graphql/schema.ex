defmodule <%= application_module %>.Schema do
  use Absinthe.Schema
  use Brando.Schema

  import_types <%= application_module %>.Schema.Types
  import_types Brando.Schema.Types

  query do
    import_brando_queries()

    # local queries
    # import_fields :client_queries
    # import_fields :post_queries
    # import_fields :project_queries
  end

  mutation do
    import_brando_mutations()

    # local mutations
    # import_fields :client_mutations
    # import_fields :post_mutations
  end
end
