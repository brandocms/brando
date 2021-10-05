defmodule Brando.DatasourcesTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Factory

  @dummy_module %{
    code: """
    this is some code
    """,
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
      },
      %{
        name: "ds",
        data: %{
          type: "datasource",
          data: %{
            module: "Elixir.Brando.DatasourcesTest.TestDatasource",
            type: "list",
            query: "all_of_them",
            code: """
            {% for entry in entries %}
            <li>{{ entry.name }}</li>
            {% endfor %}
            """
          }
        }
      }
    ],
    namespace: "Namespace",
    class: "css class"
  }

  @data_root_level_datasource [
    %{
      type: "text",
      data: %{
        text: "<p>Hello world</p>"
      }
    },
    %{
      type: "datasource",
      data: %{
        module: "Elixir.Brando.DatasourcesTest.TestDatasource",
        type: "list",
        query: "all_of_them",
        code: """
        {% for entry in entries %}
        <li>{{ entry.name }}</li>
        {% endfor %}
        """
      }
    },
    %{
      type: "text",
      data: %{
        text: "<p>Hello world</p>"
      }
    }
  ]

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
      list(:all, fn module, _ ->
        {:ok, module}
      end)

      list(:all_of_them, fn _, _ ->
        {:ok, [%{id: 1, name: "1"}, %{id: 2, name: "2"}, %{id: 3, name: "3"}]}
      end)

      list(:all_more, fn _, arg ->
        {:ok, arg}
      end)

      single(:single, fn module, _ ->
        {:ok, module}
      end)

      selection(
        :featured,
        fn _, _ ->
          {:ok,
           [
             %{id: 1, label: "The first entry"},
             %{id: 2, label: "The second entry"},
             %{id: 3, label: "The third entry"}
           ]}
        end,
        fn _, ids ->
          all = [
            %Brando.Pages.Page{
              id: 1,
              status: :draft,
              uri: "test1",
              language: "en",
              title: "The actual entry"
            },
            %Brando.Pages.Page{
              id: 2,
              status: :published,
              uri: "test2",
              language: "en",
              title: "The actual entry 2"
            },
            %Brando.Pages.Page{
              id: 3,
              status: :published,
              uri: "test3",
              language: "en",
              title: "The actual entry 3"
            }
          ]

          {:ok, Enum.filter(all, &(&1.id in ids)) |> Enum.reverse()}
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
    assert Brando.Datasource.get_list(TestDatasource, "all", nil) == {:ok, TestDatasource}
    assert Brando.Datasource.get_list(TestDatasource, "all_more", "argument") == {:ok, "argument"}
  end

  test "get_single" do
    assert Brando.Datasource.get_single(TestDatasource, "single", nil) == {:ok, TestDatasource}
  end

  test "list_selection" do
    list_result =
      {:ok,
       [
         %{id: 1, label: "The first entry"},
         %{id: 2, label: "The second entry"},
         %{id: 3, label: "The third entry"}
       ]}

    assert Brando.Datasource.list_selection(TestDatasource, "featured", nil) == list_result
  end

  test "get_selection" do
    get_result =
      {:ok,
       [
         %Brando.Content.Identifier{
           id: 3,
           status: :published,
           title: "The actual entry 3 [en]",
           absolute_url: "/test3",
           cover: nil,
           schema: Brando.Pages.Page,
           type: "Page"
         },
         %Brando.Content.Identifier{
           id: 1,
           status: :draft,
           title: "The actual entry [en]",
           absolute_url: "/test1",
           cover: nil,
           schema: Brando.Pages.Page,
           type: "Page"
         }
       ]}

    assert Brando.Datasource.get_selection(TestDatasource, "featured", [3, 1]) == get_result
  end

  test "update_datasource" do
    data = [
      %{
        type: "datasource",
        data: %{
          module: "Elixir.Brando.DatasourcesTest.TestDatasource",
          type: "list",
          query: "all_of_them",
          code: """
          {% for entry in entries %}
          <li>{{ entry.name }}</li>
          {% endfor %}
          """
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

  test "list_ids_with_datasource" do
    schema = Brando.Pages.Page

    datasource_module = __MODULE__.TestDatasource
    datasource_type = "list"
    datasource_query = "all_of_them"
    data_field = :data

    user = Factory.insert(:random_user)
    {:ok, module} = Brando.Content.create_module(@dummy_module, user)

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
            },
            %{
              name: "ds",
              data: %{
                type: "datasource",
                data: %{
                  module: "Elixir.Brando.DatasourcesTest.TestDatasource",
                  type: "list",
                  query: "all_of_them",
                  code: """
                  {% for entry in entries %}
                  <li>{{ entry.name }}</li>
                  {% endfor %}
                  """
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

    section_params = %{
      name: "green",
      namespace: "general",
      instructions: "help",
      class: "green",
      color_bg: "#000000",
      color_fg: "#FFFFFF",
      color_accent: "#FF00FF"
    }

    {:ok, section} = Brando.Content.create_section(section_params, user)

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
              type: "datasource",
              data: %{
                module: "Elixir.Brando.DatasourcesTest.TestDatasource",
                type: "list",
                query: "all_of_them",
                code: """
                {% for entry in entries %}
                <li>{{ entry.name }}</li>
                {% endfor %}
                """
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
    page_params = Factory.params_for(:page, data: @data_root_level_datasource)
    {:ok, page_with_root_level_ds} = Brando.Pages.create_page(page_params, user)

    page_params = Factory.params_for(:page, data: data_refed_datasource)
    {:ok, page_with_refed_datasource} = Brando.Pages.create_page(page_params, user)

    page_params = Factory.params_for(:page, data: data_contained_datasource)
    {:ok, page_with_contained_datasource} = Brando.Pages.create_page(page_params, user)

    page_params = Factory.params_for(:page, data: @data_no_datasource)
    {:ok, page_with_no_datasource} = Brando.Pages.create_page(page_params, user)

    found_ids =
      Brando.Datasource.list_ids_with_datasource(
        schema,
        {datasource_module, datasource_type, datasource_query},
        data_field
      )

    assert page_with_root_level_ds.id in found_ids
    assert page_with_refed_datasource.id in found_ids
    assert page_with_contained_datasource.id in found_ids
    refute page_with_no_datasource.id in found_ids

    found_ids =
      Brando.Datasource.list_ids_with_datasource(
        schema,
        datasource_module,
        data_field
      )

    assert page_with_root_level_ds.id in found_ids
    assert page_with_refed_datasource.id in found_ids
    assert page_with_contained_datasource.id in found_ids
    refute page_with_no_datasource.id in found_ids
  end
end
