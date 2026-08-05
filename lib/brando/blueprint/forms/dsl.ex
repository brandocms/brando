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
               palette_namespace: [type: :string],
               hidden: [type: {:or, [:boolean, {:tuple, [{:or, [:atom, :string]}, :any]}, {:fun, 1}]}]
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
        type: {:or, [:string, {:mfa_or_fun, 1}]},
        required: true,
        doc: "Alert content as a string or one-argument function component"
      ]
    ]
  }

  @inputs_for %Spark.Dsl.Entity{
    name: :inputs_for,
    target: Forms.Subform,
    args: [:name],
    entities: [
      sub_fields: [@input]
    ],
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
        type:
          {:or,
           [
             {:in, [:regular, :inline]},
             {:tagged_tuple, :transformer, {:or, [:atom, {:list, :atom}]}}
           ]},
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
        type: {:or, [:struct, {:map, {:or, [:atom, :string]}, :any}, nil, {:fun, 2}]},
        required: false,
        doc: "Default map/struct or a function accepting the parent entry and selected asset"
      ],
      component: [
        type: :atom,
        required: false,
        doc: "Component to use"
      ],
      listing: [
        type: {:fun, 1},
        required: false,
        doc: "Function component used to render each transformer entry"
      ],
      layout: [
        type: {:in, [:list, :grid]},
        required: false,
        default: :list,
        doc: "Transformer entry layout — :list rows, or :grid cards"
      ],
      add_entry: [
        type: :boolean,
        required: false,
        default: true,
        doc: "Render the \"Add entry\" button. Set false when every entry must carry an asset"
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
    transform: {__MODULE__, :transform_form, []},
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
        doc: "Static query options or a callback receiving the entry ID and returning a query map"
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
    verifiers: [Brando.Blueprint.Forms.Verifier]

  @doc false
  def transform_form(%Forms.Form{tabs: tabs} = form) do
    # Resolve the symbolic component tokens ONCE, here, at compile time.
    # `ComponentResolver` exists so a Blueprint can name an admin LiveComponent
    # without compile-depending on it, but it was being called from
    # `Fieldset.Field.render/1` — so every field of every form paid a
    # `Module.concat/1` (a binary build plus `String.to_atom`) on every diff,
    # for a value that is fixed at Blueprint compile time.
    #
    # Resolving here also promotes an unknown token from a render-time raise to
    # a compile-time one, which is where it belongs.
    tabs = Enum.map(tabs, &resolve_tab_components/1)

    transformers =
      for tab <- tabs,
          fieldset <- tab.fields,
          %Forms.Subform{component: nil, style: {:transformer, asset_fields}} = subform <- fieldset.fields,
          do: {subform.name, asset_fields, subform.default}

    {:ok, %{form | tabs: tabs, transformers: transformers}}
  end

  defp resolve_tab_components(%Forms.Tab{fields: fieldsets} = tab) do
    %{tab | fields: Enum.map(fieldsets, &resolve_fieldset_components/1)}
  end

  defp resolve_fieldset_components(%Forms.Fieldset{fields: fields} = fieldset) do
    %{fieldset | fields: Enum.map(fields, &resolve_field_component/1)}
  end

  # A fieldset holds `input` and `inputs_for` entities, and both carry
  # `:component`. The catch-all keeps a future entity type from crashing here.
  defp resolve_field_component(%{component: component} = field),
    do: %{field | component: Forms.ComponentResolver.resolve(component)}

  defp resolve_field_component(field), do: field
end
