defmodule Brando.DatasourcesTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Factory

  @dummy_datamodule %{
    code: """
    {% for entry in entries %}
    <li>{{ entry.name }}</li>
    {% endfor %}
    """,
    datasource: true,
    datasource_module: "Elixir.Brando.DatasourcesTest.TestDatasource",
    datasource_type: "list",
    datasource_query: "all_of_them",
    name: "Module",
    help_text: "Help text",
    refs: [
      %{
        name: "p",
        data: %{
          type: "text",
          data: %{
            text: "<p>Hello world</p>"
          }
        }
      }
    ],
    namespace: "Namespace",
    class: "css class"
  }

  @data_no_datasource [
    %{
      type: "text",
      data: %{
        text: "<p>Hello world</p>"
      }
    },
    %{
      type: "text",
      data: %{
        text: "<p>Hello world</p>"
      }
    }
  ]

  defmodule TestDatasource do
    use Brando.Datasource

    datasources do
      list(:all, fn module, _, _ ->
        {:ok, module}
      end)

      list(:all_of_them, fn _, _, _ ->
        {:ok, [%{id: 1, name: "1"}, %{id: 2, name: "2"}, %{id: 3, name: "3"}]}
      end)

      list(:all_more, fn _, lang, vars ->
        {:ok, vars, lang}
      end)

      single(:single, fn module, _ ->
        {:ok, module}
      end)

      selection(
        :featured,
        fn _, _, _ ->
          Brando.Content.list_identifiers(Brando.Pages.Page, %{
            language: "en",
            order: "asc language, asc entry_id"
          })
        end,
        fn identifiers ->
          entry_ids = Enum.map(identifiers, & &1.entry_id)

          results =
            from t in Brando.Pages.Page,
              where: t.id in ^entry_ids,
              order_by: fragment("array_position(?, ?)", ^entry_ids, t.id)

          {:ok, Brando.repo().all(results)}
        end
      )
    end
  end

  alias Brando.DatasourcesTest.TestDatasource

  test "__datasources__" do
    assert TestDatasource.__datasources__(:list) == [:all_more, :all_of_them, :all]
  end

  test "list datasources" do
    assert Brando.Datasource.list_datasources() == {:ok, []}
  end

  test "list datasource keys" do
    assert Brando.Datasource.list_datasource_keys(TestDatasource) ==
             {:ok, %{list: [:all_more, :all_of_them, :all], single: [], selection: [:featured]}}
  end

  test "get_list" do
    assert Brando.Datasource.get_list(TestDatasource, "all", nil, "en") == {:ok, TestDatasource}

    assert Brando.Datasource.get_list(TestDatasource, "all_more", "argument", "en") ==
             {:ok, "argument", "en"}
  end

  test "get_single" do
    assert Brando.Datasource.get_single(TestDatasource, "single", nil) == {:ok, TestDatasource}
  end

  test "list_selection" do
    usr = Factory.insert(:random_user)

    {:ok, p1} = Brando.Pages.create_page(Factory.params_for(:page, title: "Title 1"), usr)
    {:ok, p2} = Brando.Pages.create_page(Factory.params_for(:page, title: "Title 2"), usr)
    {:ok, p3} = Brando.Pages.create_page(Factory.params_for(:page, title: "Title 3"), usr)

    {:ok, identifiers} =
      Brando.Datasource.list_selection(TestDatasource, "featured", nil, nil)

    assert Enum.map(identifiers, & &1.entry_id) == [p1.id, p2.id, p3.id]
  end

  test "get_selection" do
    usr = Factory.insert(:random_user)

    {:ok, p1} = Brando.Pages.create_page(Factory.params_for(:page, title: "Title 1"), usr)
    {:ok, p2} = Brando.Pages.create_page(Factory.params_for(:page, title: "Title 2"), usr)
    {:ok, p3} = Brando.Pages.create_page(Factory.params_for(:page, title: "Title 3"), usr)

    # get identifier ids
    {:ok, identifiers} =
      Brando.Pages.Page
      |> Brando.Content.list_identifiers(%{order: "asc id"})

    {:ok, entries} =
      Brando.Datasource.get_selection(TestDatasource, "featured", Enum.map(identifiers, & &1.id))

    assert Enum.map(entries, & &1.id) == [p1.id, p2.id, p3.id]
  end

  test "update_datasource" do
    user = Factory.insert(:random_user)
    {:ok, module} = Brando.Content.create_module(@dummy_datamodule, user)

    data = [
      %{
        type: "module",
        data: %{
          datasource: true,
          module_id: module.id
        }
      }
    ]

    page_params = Factory.params_for(:page, data: data)
    user = Factory.insert(:random_user)
    {:ok, p1} = Brando.Pages.create_page(page_params, user)
    assert p1.html == "\n<li>1</li>\n\n<li>2</li>\n\n<li>3</li>\n\n"

    assert Brando.Datasource.update_datasource(TestDatasource, :pass_through) ==
             {:ok, :pass_through}
  end

  test "list_ids_with_datamodule" do
    schema = Brando.Pages.Page

    datasource_module = __MODULE__.TestDatasource
    datasource_type = "list"
    datasource_query = "all_of_them"
    data_field = :data

    user = Factory.insert(:random_user)
    {:ok, module} = Brando.Content.create_module(@dummy_datamodule, user)

    data_refed_datasource = [
      %{
        type: "text",
        data: %{
          text: "<p>Hello world</p>"
        }
      },
      %{
        type: "module",
        data: %{
          datasource: true,
          module_id: module.id,
          refs: [
            %{
              name: "p",
              data: %{
                type: "text",
                data: %{
                  text: "<p>Hello world</p>"
                }
              }
            }
          ]
        }
      },
      %{
        type: "text",
        data: %{
          text: "<p>Hello world</p>"
        }
      }
    ]

    palette_params = %{
      status: :published,
      name: "green",
      key: "green",
      namespace: "general",
      instructions: "help",
      colors: [
        %{name: "Background color", key: "color_bg", hex_value: "#000000"},
        %{name: "Foreground color", key: "color_fg", hex_value: "#FFFFFF"},
        %{name: "Accent color", key: "color_accent", hex_value: "#FF00FF"}
      ]
    }

    {:ok, palette} = Brando.Content.create_palette(palette_params, user)

    data_contained_datasource = [
      %{
        type: "text",
        data: %{
          text: "<p>Hello world</p>"
        }
      },
      %{
        type: "container",
        data: %{
          palette_id: palette.id,
          blocks: [
            %{
              type: "text",
              data: %{
                text: "<p>Hello world</p>"
              }
            },
            %{
              type: "module",
              data: %{
                datasource: true,
                module_id: module.id,
                refs: [
                  %{
                    name: "p",
                    data: %{
                      type: "text",
                      data: %{
                        text: "<p>Hello world</p>"
                      }
                    }
                  }
                ]
              }
            }
          ]
        }
      },
      %{
        type: "text",
        data: %{
          text: "<p>Hello world</p>"
        }
      }
    ]

    # insert pages
    page_params = Factory.params_for(:page, data: data_refed_datasource)
    {:ok, page_with_refed_datasource} = Brando.Pages.create_page(page_params, user)

    page_params = Factory.params_for(:page, data: data_contained_datasource)
    {:ok, page_with_contained_datasource} = Brando.Pages.create_page(page_params, user)

    page_params = Factory.params_for(:page, data: @data_no_datasource)
    {:ok, page_with_no_datasource} = Brando.Pages.create_page(page_params, user)

    found_ids =
      Brando.Datasource.list_ids_with_datamodule(
        schema,
        {datasource_module, datasource_type, datasource_query},
        data_field
      )

    assert page_with_refed_datasource.id in found_ids
    assert page_with_contained_datasource.id in found_ids
    refute page_with_no_datasource.id in found_ids

    found_ids =
      Brando.Datasource.list_ids_with_datamodule(
        schema,
        datasource_module,
        data_field
      )

    assert page_with_refed_datasource.id in found_ids
    assert page_with_contained_datasource.id in found_ids
    refute page_with_no_datasource.id in found_ids
  end
end
