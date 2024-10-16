defmodule Brando.Blueprint.FormsTest do
  use ExUnit.Case

  test "default form" do
    assert Brando.BlueprintTest.Project.__form__() ==
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
             }
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
    assert Brando.BlueprintTest.Project.__forms__() == [
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
           ]
  end
end
