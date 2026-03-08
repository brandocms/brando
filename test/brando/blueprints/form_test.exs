defmodule Brando.Blueprint.FormsTest do
  use ExUnit.Case
  import Brando.Test.Support, only: [strip_spark_metadata: 1]

  defmodule BlocksHiddenOpts do
    use Brando.Blueprint,
      application: "Brando",
      domain: "Tests",
      schema: "BlocksHiddenOpts",
      singular: "blocks_hidden_opts",
      plural: "blocks_hidden_opts",
      gettext_module: Brando.Gettext

    attributes do
      attribute :title, :string
    end

    forms do
      form do
        blocks :blocks, hidden: {:title, "hide"}

        tab "Content" do
          fieldset do
            input :title, :text
          end
        end
      end

      form :with_fn do
        blocks :blocks, hidden: &__MODULE__.hide_blocks?/1

        tab "Content" do
          fieldset do
            input :title, :text
          end
        end
      end
    end

    def hide_blocks?(_form), do: false
  end

  test "default form" do
    assert strip_spark_metadata(Brando.BlueprintTest.Project.__form__()) ==
             strip_spark_metadata(%Brando.Blueprint.Forms.Form{
               __identifier__: :default,
               name: :default,
               blocks: [
                 %Brando.Blueprint.Forms.Input{
                   name: :blocks,
                   type: :blocks,
                   component: nil,
                   opts: []
                 }
               ],
               tabs: [
                 %Brando.Blueprint.Forms.Tab{
                   fields: [
                     %Brando.Blueprint.Forms.Fieldset{
                       fields: [
                         %Brando.Blueprint.Forms.Input{
                           name: :title,
                           opts: [],
                           component: nil,
                           type: :text
                         },
                         %Brando.Blueprint.Forms.Input{
                           name: :slug,
                           opts: [from: :title],
                           component: nil,
                           type: :slug
                         }
                       ],
                       size: :half,
                       style: :regular
                     }
                   ],
                   name: "Content"
                 },
                 %Brando.Blueprint.Forms.Tab{
                   fields: [
                     %Brando.Blueprint.Forms.Fieldset{
                       fields: [
                         %Brando.Blueprint.Forms.Subform{
                           cardinality: :many,
                           component: nil,
                           default: %{},
                           name: :properties,
                           style: :inline,
                           sub_fields: [
                             %Brando.Blueprint.Forms.Input{
                               name: :key,
                               opts: [placeholder: "Key"],
                               component: nil,
                               type: :text
                             },
                             %Brando.Blueprint.Forms.Input{
                               name: :value,
                               opts: [placeholder: "Val"],
                               component: nil,
                               type: :text
                             }
                           ],
                           listing: nil
                         }
                       ],
                       size: :full,
                       style: :regular
                     }
                   ],
                   name: "Properties"
                 }
               ]
             })
  end

  test "get_tab_for_field" do
    assert Brando.Blueprint.Forms.get_tab_for_field(
             :slug,
             Brando.BlueprintTest.Project.__form__()
           ) ==
             "Content"

    assert Brando.Blueprint.Forms.get_tab_for_field(
             :properties,
             Brando.BlueprintTest.Project.__form__()
           ) ==
             "Properties"

    # get the first one if we don't find the tab
    assert Brando.Blueprint.Forms.get_tab_for_field(
             :non_existing,
             Brando.BlueprintTest.Project.__form__()
           ) == "Content"
  end

  test "forms" do
    assert strip_spark_metadata(Brando.BlueprintTest.Project.__forms__()) ==
             strip_spark_metadata([
               %Brando.Blueprint.Forms.Form{
                 __identifier__: :default,
                 name: :default,
                 blocks: [
                   %Brando.Blueprint.Forms.Input{
                     name: :blocks,
                     type: :blocks,
                     component: nil,
                     opts: []
                   }
                 ],
                 tabs: [
                   %Brando.Blueprint.Forms.Tab{
                     fields: [
                       %Brando.Blueprint.Forms.Fieldset{
                         fields: [
                           %Brando.Blueprint.Forms.Input{
                             name: :title,
                             opts: [],
                             component: nil,
                             type: :text
                           },
                           %Brando.Blueprint.Forms.Input{
                             name: :slug,
                             opts: [from: :title],
                             component: nil,
                             type: :slug
                           }
                         ],
                         size: :half,
                         style: :regular
                       }
                     ],
                     name: "Content"
                   },
                   %Brando.Blueprint.Forms.Tab{
                     fields: [
                       %Brando.Blueprint.Forms.Fieldset{
                         fields: [
                           %Brando.Blueprint.Forms.Subform{
                             cardinality: :many,
                             component: nil,
                             default: %{},
                             name: :properties,
                             style: :inline,
                             sub_fields: [
                               %Brando.Blueprint.Forms.Input{
                                 name: :key,
                                 opts: [placeholder: "Key"],
                                 component: nil,
                                 type: :text
                               },
                               %Brando.Blueprint.Forms.Input{
                                 name: :value,
                                 opts: [placeholder: "Val"],
                                 component: nil,
                                 type: :text
                               }
                             ],
                             listing: nil
                           }
                         ],
                         size: :full,
                         style: :regular
                       }
                     ],
                     name: "Properties"
                   }
                 ]
               },
               %Brando.Blueprint.Forms.Form{
                 __identifier__: :extra,
                 name: :extra,
                 tabs: [
                   %Brando.Blueprint.Forms.Tab{
                     fields: [
                       %Brando.Blueprint.Forms.Fieldset{
                         fields: [
                           %Brando.Blueprint.Forms.Input{
                             name: :title,
                             opts: [],
                             component: nil,
                             type: :text
                           }
                         ],
                         size: :half,
                         style: :regular
                       }
                     ],
                     name: "Test"
                   }
                 ]
               }
             ])
  end

  test "blocks accepts hidden opts" do
    default_form = BlocksHiddenOpts.__form__()
    with_fn_form = BlocksHiddenOpts.__form__(:with_fn)

    assert [%Brando.Blueprint.Forms.Input{name: :blocks, opts: opts}] = default_form.blocks
    assert Keyword.get(opts, :hidden) == {:title, "hide"}

    assert [%Brando.Blueprint.Forms.Input{name: :blocks, opts: fn_opts}] = with_fn_form.blocks
    assert is_function(Keyword.get(fn_opts, :hidden), 1)
  end
end
