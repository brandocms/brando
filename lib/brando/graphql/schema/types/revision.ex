defmodule Brando.GraphQL.Schema.Types.Revision do
  use Brando.Web, :absinthe

  object :revision do
    field :active, :boolean
    field :entry_id, :integer
    field :entry_type, :string
    field :encoded_entry, :string
    field :metadata, :json
    field :revision, :integer
    field :protected, :boolean
    field :creator, :user, resolve: dataloader(Brando.Pages)
    field :inserted_at, :time
    field :updated_at, :time
  end

  @desc "Filtering options for revision"
  input_object :revision_filter do
    field :entry_id, :id
    field :entry_type, :string
    field :active, :boolean
  end

  object :revision_queries do
    @desc "Get all revisions"
    field :revisions, type: list_of(:revision) do
      arg :order, :order,
        default_value: [{:asc, :entry_type}, {:desc, :entry_id}, {:desc, :revision}]

      arg :limit, :integer, default_value: 100
      arg :offset, :integer, default_value: 0
      arg :filter, :revision_filter
      resolve &Brando.Revisions.RevisionResolver.all/2
    end
  end
end
