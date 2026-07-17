defmodule Brando.Blueprint.FormsTest do
  use ExUnit.Case
  import Brando.Test.Support, only: [strip_spark_metadata: 1]

  test "default form" do
    assert strip_spark_metadata(Brando.BlueprintTest.Project.__form__()) ==
             strip_spark_metadata(expected_default_form())
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

  test "field lookup resolves foreign keys while preferring exact field names" do
    form =
      lookup_form([
        {"Relations", [owner: :select]},
        {"Identifiers", [owner_id: :text]},
        {"Media", [cover_video: :video]}
      ])

    assert Brando.Blueprint.Forms.get_tab_for_field(:owner_id, form) == "Identifiers"
    assert %Brando.Blueprint.Forms.Input{name: :owner_id} = Brando.Blueprint.Forms.get_field(:owner_id, form)

    assert Brando.Blueprint.Forms.get_tab_for_field(:cover_video_id, form) == "Media"

    assert %Brando.Blueprint.Forms.Input{name: :cover_video} =
             Brando.Blueprint.Forms.get_field(:cover_video_id, form)
  end

  test "forms" do
    assert strip_spark_metadata(Brando.BlueprintTest.Project.__forms__()) ==
             strip_spark_metadata([
               expected_default_form(),
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
    default_form = Brando.TraitTest.Project.__form__()
    with_fn_form = Brando.TraitTest.Project.__form__(:with_fn)

    assert [%Brando.Blueprint.Forms.Input{name: :blocks, opts: opts}] = default_form.blocks
    assert Keyword.get(opts, :hidden) == {:title, "hide"}

    assert [%Brando.Blueprint.Forms.Input{name: :blocks, opts: fn_opts}] = with_fn_form.blocks
    assert is_function(Keyword.get(fn_opts, :hidden), 1)
  end

  defp lookup_form(tab_fields) do
    tabs =
      Enum.map(tab_fields, fn {tab_name, fields} ->
        inputs = Enum.map(fields, fn {name, type} -> %Brando.Blueprint.Forms.Input{name: name, type: type} end)
        fieldset = %Brando.Blueprint.Forms.Fieldset{fields: inputs}
        %Brando.Blueprint.Forms.Tab{name: tab_name, fields: [fieldset]}
      end)

    %Brando.Blueprint.Forms.Form{tabs: tabs}
  end

  defp expected_default_form do
    %Brando.Blueprint.Forms.Form{
      __identifier__: :default,
      name: :default,
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
end
