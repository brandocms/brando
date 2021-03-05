defmodule Brando.GraphQL.Schema.Types.Pagination do
  use Brando.Web, :absinthe

  object :pagination_meta do
    field :current_page, non_null(:integer)
    field :previous_page, :integer
    field :next_page, :integer
    field :total_entries, non_null(:integer)
    field :total_pages, non_null(:integer)
  end
end
