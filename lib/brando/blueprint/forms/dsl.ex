defmodule Brando.Blueprint.Forms.Dsl do
  alias Brando.Blueprint.Forms

  @input %Spark.Dsl.Entity{
    name: :input,
    args: [:name, :type, {:optional, :opts}],
    target: Forms.Input,
    schema: [
      opts: [
        type: :keyword_list,
        required: false,
        default: [],
        doc: "Input options"
      ],
      name: [
        type: :atom,
        required: true,
        doc: "Input field name"
      ],
      type: [
        type: {:or, [:atom, {:tuple, [{:in, [:live_component]}, :module]}, {:fun, 1}]},
        required: true,
        doc: "Type of input. Atom or &component/1 function"
      ]
    ]
  }

  @blocks %Spark.Dsl.Entity{
    name: :blocks,
    args: [:name, {:optional, :opts}],
    target: Forms.Input,
    auto_set_fields: [type: :blocks],
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "Input field name"
      ],
      opts: [
        type:
          {:or,
           [
             keyword_list: [
               label: [type: :string],
               module_set: [type: :string],
               template_namespace: [type: :string],
               palette_namespace: [type: :string]
             ]
           ]},
        required: false,
        default: [],
        doc: "Block options"
      ]
    ]
  }

  @alert %Spark.Dsl.Entity{
    name: :alert,
    args: [:type, {:optional, :content}],
    target: Forms.Alert,
    schema: [
      type: [
        type: {:in, [:warning, :error, :info]},
        required: true,
        doc: "Alert type"
      ],
      content: [
        type: {:or, [:mfa, :string]},
        required: true,
        doc: "Alert content as string or component"
      ]
    ]
  }

  # TODO: We should add transformers to the form schema through
  # a Spark transformer when we add an inputs_for with style set as
  # style: {:transformer, :image} # , and
  # default: &__MODULE__.default_image/2,
  @inputs_for %Spark.Dsl.Entity{
    name: :inputs_for,
    target: Forms.Subform,
    args: [:name],
    entities: [
      sub_fields: [@input]
    ],
    # transform: {Forms.Subform, :transform, []},
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "Subform field name"
      ],
      label: [
        type: :string,
        required: false,
        doc: "Subform field label"
      ],
      cardinality: [
        type: {:in, [:one, :many]},
        required: false,
        default: :one,
        doc: "Cardinality"
      ],
      style: [
        type: {:in, [:regular, :inline, {:transformer, :atom}]},
        required: false,
        default: :regular,
        doc: "Style"
      ],
      size: [
        type: {:in, [:full, :half, :third, :quarter]},
        required: false,
        default: :full,
        doc: "Size"
      ],
      default: [
        type: :any,
        required: false,
        doc: "Default value"
      ],
      component: [
        type: :atom,
        required: false,
        doc: "Component to use"
      ],
      listing: [
        type: :atom,
        required: false,
        doc: "Listing to use"
      ],
      instructions: [
        type: :string,
        required: false,
        doc: "Instructions"
      ]
    ]
  }

  @fieldset %Spark.Dsl.Entity{
    name: :fieldset,
    target: Forms.Fieldset,
    entities: [
      fields: [
        @input,
        @inputs_for
      ]
    ],
    schema: [
      size: [
        type: {:in, [:full, :half, :third, :quarter]},
        required: false,
        default: :full,
        doc: "Size"
      ],
      align: [
        type: {:in, [:start, :center, :end]},
        required: false,
        default: :start,
        doc: "Align"
      ],
      shaded: [
        type: :boolean,
        required: false,
        default: false,
        doc: "Shaded"
      ],
      style: [
        type: {:in, [:regular, :inline]},
        required: false,
        default: :regular,
        doc: "Style"
      ],
      opts: [
        type: :keyword_list,
        required: false,
        doc: "Fieldset options"
      ]
    ]
  }

  @tab %Spark.Dsl.Entity{
    name: :tab,
    target: Forms.Tab,
    args: [:name],
    entities: [
      fields: [@fieldset],
      alerts: [@alert]
    ],
    schema: [
      name: [
        type: :string,
        required: true,
        doc: "Tab name"
      ]
    ]
  }

  @form %Spark.Dsl.Entity{
    name: :form,
    identifier: :name,
    describe: """
    Declares a form
    """,
    examples: [
      """
      form do
        default_params %{status: :draft}
      end
      """
    ],
    args: [{:optional, :name, :default}],
    entities: [
      blocks: [@blocks],
      tabs: [@tab]
    ],
    target: Forms.Form,
    schema: [
      name: [
        type: :atom,
        required: false,
        default: :default,
        doc: "Form name"
      ],
      default_params: [
        type: {:map, {:or, [:atom, :string]}, :any},
        required: false,
        doc: "Default params"
      ],
      query: [
        type: {:or, [:map, nil, {:mfa_or_fun, 1}]},
        required: false,
        default: nil,
        doc: "Form query"
      ],
      after_save: [
        type: {:mfa_or_fun, 2},
        required: false,
        doc: "Function to call after saving form. Takes the saved entry and current_user"
      ],
      redirect_on_save: [
        type: {:mfa_or_fun, 3},
        required: false,
        doc: "Override redirection on save. Takes socket, entry, mutation_type"
      ]
    ]
  }

  @root %Spark.Dsl.Section{
    name: :forms,
    entities: [@form],
    top_level?: false
  }

  @moduledoc false
  use Spark.Dsl.Extension,
    sections: [@root],
    transformers: [],
    imports: [Brando.Blueprint.Forms.Legacy]
end
