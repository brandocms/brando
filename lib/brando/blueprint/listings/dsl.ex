defmodule Brando.Blueprint.Listings.Dsl do
  alias Brando.Blueprint.Listings

  @child_listing %Spark.Dsl.Entity{
    name: :child_listing,
    target: Listings.ChildListing,
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "Child listing name"
      ],
      schema: [
        type: :atom,
        required: true,
        doc: "Child listing schema"
      ]
    ]
  }

  @export %Spark.Dsl.Entity{
    name: :export,
    args: [:name],
    target: Listings.Export,
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "Export name"
      ],
      label: [
        type: :string,
        required: true,
        doc: "Export label"
      ],
      type: [
        type: :atom,
        default: :csv,
        doc: "Type of export"
      ],
      query: [
        type: :map,
        required: false,
        default: %{},
        doc: "Export query"
      ],
      fields: [
        type: {:list, :atom},
        required: true,
        doc: "List of fields to export"
      ],
      description: [
        type: :string,
        required: false,
        doc: "Export description"
      ]
    ]
  }

  @filter %Spark.Dsl.Entity{
    name: :filter,
    target: Listings.Filter,
    schema: [
      label: [
        type: :string,
        required: true,
        doc: "Filter label"
      ],
      filter: [
        type: :string,
        required: true,
        doc: "Filter"
      ]
    ]
  }

  @selection_action %Spark.Dsl.Entity{
    name: :selection_action,
    target: Listings.Action,
    schema: [
      label: [
        type: :string,
        required: false,
        doc: "Action label"
      ],
      event: [
        type: {:or, [:string, {:struct, Phoenix.LiveView.JS}]},
        required: false,
        doc: "Action event"
      ]
    ]
  }

  @action %Spark.Dsl.Entity{
    name: :action,
    target: Listings.Action,
    schema: [
      label: [
        type: :string,
        required: false,
        doc: "Sort label"
      ],
      event: [
        type: {:or, [:string, :any]},
        required: false,
        doc: "Action event"
      ],
      confirm: [
        type: {:or, [:boolean, :string]},
        required: false,
        default: false,
        doc: "Confirm message"
      ]
    ]
  }

  @sort %Spark.Dsl.Entity{
    name: :sort,
    target: Listings.Sort,
    args: [:key],
    schema: [
      key: [
        type: :atom,
        required: true,
        doc: "Sort key"
      ],
      label: [
        type: :string,
        required: true,
        doc: "Sort label"
      ],
      order: [
        type: :any,
        required: true,
        doc: "Order instructions"
      ]
    ]
  }

  @listing %Spark.Dsl.Entity{
    name: :listing,
    identifier: :name,
    args: [{:optional, :name, :default}],
    entities: [
      actions: [@action],
      sorts: [@sort],
      selection_actions: [@selection_action],
      filters: [@filter],
      child_listings: [@child_listing],
      exports: [@export]
    ],
    target: Listings.Listing,
    schema: [
      name: [
        type: :atom,
        required: false,
        default: :default,
        doc: "Listing name"
      ],
      component: [
        type: {:fun, 1},
        required: false,
        doc: "Listing row component"
      ],
      default_actions: [
        type: :boolean,
        required: false,
        default: true,
        doc: "Include default actions"
      ],
      query: [
        type: :map,
        required: false,
        default: %{},
        doc: "Listing query"
      ],
      sortable: [
        type: :boolean,
        required: false,
        default: true,
        doc: "Listing is sortable"
      ],
      limit: [
        type: :integer,
        required: false,
        doc: "How many entries to show per page"
      ]
    ]
  }

  @root %Spark.Dsl.Section{
    name: :listings,
    entities: [@listing],
    top_level?: false
  }

  @moduledoc false
  use Spark.Dsl.Extension,
    sections: [@root],
    transformers: []
end
