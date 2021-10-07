defmodule Brando.Blueprint.FormTest do
  use ExUnit.Case

  test "default form" do
    assert Brando.BlueprintTest.Project.__form__() ==
             %Brando.Blueprint.Form{
               name: :default,
               tabs: [
                 %Brando.Blueprint.Form.Tab{
                   fields: [
                     %Brando.Blueprint.Form.Fieldset{
                       fields: [
                         %Brando.Blueprint.Form.Input{
                           name: :title,
                           opts: [],
                           template: nil,
                           type: :text
                         },
                         %Brando.Blueprint.Form.Input{
                           name: :slug,
                           opts: [from: :title],
                           template: nil,
                           type: :slug
                         }
                       ],
                       size: :half,
                       style: :regular
                     }
                   ],
                   name: "Content"
                 },
                 %Brando.Blueprint.Form.Tab{
                   fields: [
                     %Brando.Blueprint.Form.Fieldset{
                       fields: [
                         %Brando.Blueprint.Form.Subform{
                           cardinality: :many,
                           component: nil,
                           default: %{},
                           field: :properties,
                           style: :inline,
                           sub_fields: [
                             %Brando.Blueprint.Form.Input{
                               name: :key,
                               opts: [placeholder: "Key"],
                               template: nil,
                               type: :text
                             },
                             %Brando.Blueprint.Form.Input{
                               name: :value,
                               opts: [placeholder: "Val"],
                               template: nil,
                               type: :text
                             }
                           ]
                         },
                         %Brando.Blueprint.Form.Input{
                           name: :data,
                           opts: [],
                           template: nil,
                           type: :blocks
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
    assert Brando.Blueprint.Form.get_tab_for_field(:slug, Brando.BlueprintTest.Project.__form__()) ==
             "Content"

    assert Brando.Blueprint.Form.get_tab_for_field(
             :properties,
             Brando.BlueprintTest.Project.__form__()
           ) ==
             "Properties"

    assert Brando.Blueprint.Form.get_tab_for_field(:data, Brando.BlueprintTest.Project.__form__()) ==
             "Properties"

    assert Brando.Blueprint.Form.get_tab_for_field(
             :non_existing,
             Brando.BlueprintTest.Project.__form__()
           ) ==
             nil
  end

  test "forms" do
    assert Brando.BlueprintTest.Project.__forms__() == [
             %Brando.Blueprint.Form{
               name: :default,
               tabs: [
                 %Brando.Blueprint.Form.Tab{
                   fields: [
                     %Brando.Blueprint.Form.Fieldset{
                       fields: [
                         %Brando.Blueprint.Form.Input{
                           name: :title,
                           opts: [],
                           template: nil,
                           type: :text
                         },
                         %Brando.Blueprint.Form.Input{
                           name: :slug,
                           opts: [from: :title],
                           template: nil,
                           type: :slug
                         }
                       ],
                       size: :half,
                       style: :regular
                     }
                   ],
                   name: "Content"
                 },
                 %Brando.Blueprint.Form.Tab{
                   fields: [
                     %Brando.Blueprint.Form.Fieldset{
                       fields: [
                         %Brando.Blueprint.Form.Subform{
                           cardinality: :many,
                           component: nil,
                           default: %{},
                           field: :properties,
                           style: :inline,
                           sub_fields: [
                             %Brando.Blueprint.Form.Input{
                               name: :key,
                               opts: [placeholder: "Key"],
                               template: nil,
                               type: :text
                             },
                             %Brando.Blueprint.Form.Input{
                               name: :value,
                               opts: [placeholder: "Val"],
                               template: nil,
                               type: :text
                             }
                           ]
                         },
                         %Brando.Blueprint.Form.Input{
                           name: :data,
                           opts: [],
                           template: nil,
                           type: :blocks
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
             %Brando.Blueprint.Form{
               name: :extra,
               tabs: [
                 %Brando.Blueprint.Form.Tab{
                   fields: [
                     %Brando.Blueprint.Form.Fieldset{
                       fields: [
                         %Brando.Blueprint.Form.Input{
                           name: :title,
                           opts: [],
                           template: nil,
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
