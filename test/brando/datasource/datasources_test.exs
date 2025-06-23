defmodule Brando.DatasourcesTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Factory

  @dummy_module %{
    code: """
    TEST
    """,
    name: "Module",
    help_text: "Help text",
    refs: [],
    namespace: "Namespace",
    class: "css class"
  }
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
        uid: "1wUr4ZLoOx53fqIslbP1dg",
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

  defmodule TestDatasource do
    use Brando.Blueprint,
      application: "BrandoIntegration",
      domain: "Tests",
      schema: "TestDatasource",
      singular: "test_datasource",
      plural: "test_datasources",
      gettext_module: Brando.Gettext

    datasources do
      datasource :all do
        type :list

        list(fn module, _, _ ->
          {:ok, module}
        end)
      end

      datasource :all_of_them do
        type :list

        list(fn _, _, _ ->
          {:ok, [%{id: 1, name: "1"}, %{id: 2, name: "2"}, %{id: 3, name: "3"}]}
        end)
      end

      datasource :all_more do
        type :list

        list(fn _, lang, vars ->
          {:ok, vars, lang}
        end)
      end

      datasource :single do
        type :single

        list(fn module, _, _ ->
          {:ok, module}
        end)

        get(fn id ->
          {:ok, id}
        end)
      end

      datasource :featured do
        type :selection

        list(fn _, _, _ ->
          Brando.Content.list_identifiers(Brando.Pages.Page, %{
            language: "en",
            order: "asc language, asc entry_id"
          })
        end)

        get(fn identifiers ->
          entry_ids = Enum.map(identifiers, & &1.entry_id)

          results =
            from t in Brando.Pages.Page,
              where: t.id in ^entry_ids,
              order_by: fragment("array_position(?, ?)", ^entry_ids, t.id)

          {:ok, Brando.Repo.all(results)}
        end)
      end
    end
  end

  alias Brando.DatasourcesTest.TestDatasource

  test "__datasources__" do
    assert Brando.Datasource.datasources(TestDatasource, :list) == [:all, :all_of_them, :all_more]
  end

  test "list datasources" do
    assert Brando.Datasource.list_datasources() == {:ok, []}
  end

  test "list datasource keys" do
    assert Brando.Datasource.list_datasource_keys(TestDatasource) ==
             {:ok, %{list: [:all_more, :all_of_them, :all], selection: [:featured], single: [:single]}}
  end

  test "get_list" do
    assert Brando.Datasource.list_results(TestDatasource, "all", nil, "en") ==
             {:ok, TestDatasource}

    assert Brando.Datasource.list_results(TestDatasource, "all_more", "argument", "en") ==
             {:ok, "argument", "en"}
  end

  test "get_single" do
    assert Brando.Datasource.get_single(TestDatasource, "single", %Brando.Content.Identifier{}) ==
             {:ok, %Brando.Content.Identifier{}}
  end

  test "list_selection" do
    usr = Factory.insert(:random_user)

    {:ok, p1} = Brando.Pages.create_page(Factory.params_for(:page, title: "Title 1"), usr)
    {:ok, p2} = Brando.Pages.create_page(Factory.params_for(:page, title: "Title 2"), usr)
    {:ok, p3} = Brando.Pages.create_page(Factory.params_for(:page, title: "Title 3"), usr)

    {:ok, identifiers} =
      Brando.Datasource.list_results(TestDatasource, "featured", nil, nil)

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
      Brando.Content.get_entries_from_identifiers(identifiers)

    assert Enum.map(entries, & &1.id) == [p1.id, p2.id, p3.id]
  end

  test "update_datasource" do
    user = Factory.insert(:random_user)
    {:ok, module} = Brando.Content.create_module(@dummy_datamodule, user)

    page_params = Factory.params_for(:page)

    simple_blocks = [
      %Brando.Pages.Page.Blocks{
        block: %Brando.Content.Block{
          type: :module,
          source: "Elixir.Brando.Pages.Page.Blocks",
          module_id: module.id,
          uid: "1wUr4ZLoOx53fqIslbP1dg",
          refs: [],
          vars: []
        }
      }
      |> Ecto.Changeset.change()
      |> Map.put(:action, :insert)
    ]

    page_cs = Brando.Pages.Page.changeset(%Brando.Pages.Page{}, page_params, user)
    page_cs = Ecto.Changeset.put_assoc(page_cs, :entry_blocks, simple_blocks)
    page_cs = Map.put(page_cs, :action, :insert)

    {:ok, p1} = Brando.Pages.create_page(page_cs, user)
    {:ok, p1} = Brando.Villain.render_entry(Brando.Pages.Page, p1.id)
    assert p1.rendered_blocks == "\n<li>1</li>\n\n<li>2</li>\n\n<li>3</li>\n\n"
  end

  test "list_ids_with_datamodule" do
    schema = Brando.Pages.Page
    datasource_module = __MODULE__.TestDatasource

    user = Factory.insert(:random_user)
    {:ok, module} = Brando.Content.create_module(@dummy_datamodule, user)
    {:ok, m2} = Brando.Content.create_module(@dummy_module, user)

    data_refed_datasource = [
      %{
        block: %{
          type: :module,
          datasource: true,
          module_id: module.id,
          source: "Elixir.Brando.Pages.Page.Blocks",
          refs: [
            %{
              name: "p",
              uid: "1wUr4ZLoOx53fqIslbP1dx",
              data: %Brando.Villain.Blocks.TextBlock{
                type: "text",
                data: %Brando.Villain.Blocks.TextBlock.Data{
                  text: "<p>Hello world</p>"
                }
              }
            }
          ]
        }
      }
    ]

    data_no_datasource = [
      %{
        block: %{
          type: :module,
          datasource: false,
          module_id: m2.id,
          source: "Elixir.Brando.Pages.Page.Blocks",
          refs: [
            %{
              name: "p",
              uid: "1wUr4ZLoOx53fqIslbP1df",
              data: %Brando.Villain.Blocks.TextBlock{
                type: "text",
                data: %Brando.Villain.Blocks.TextBlock.Data{
                  text: "<p>Hello world</p>"
                }
              }
            }
          ]
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
        block: %{
          type: :container,
          source: "Elixir.Brando.Pages.Page.Blocks",
          palette_id: palette.id,
          children: [
            %{
              type: :module,
              datasource: true,
              module_id: module.id,
              refs: [
                %{
                  name: "p",
                  uid: "1wUr4ZLoOx5zfqIslbP1dg",
                  data: %Brando.Villain.Blocks.TextBlock{
                    type: "text",
                    data: %Brando.Villain.Blocks.TextBlock.Data{
                      text: "<p>Hello world</p>"
                    }
                  }
                }
              ]
            }
          ]
        }
      }
    ]

    # insert pages
    page_params = Factory.params_for(:page)

    page_cs =
      %Brando.Pages.Page{}
      |> Brando.Pages.Page.changeset(page_params, user)
      |> Ecto.Changeset.put_assoc(:entry_blocks, data_refed_datasource)
      |> Map.put(:action, :insert)

    {:ok, page_with_refed_datasource} = Brando.Pages.create_page(page_cs, user)

    page_cs =
      %Brando.Pages.Page{}
      |> Brando.Pages.Page.changeset(page_params, user)
      |> Ecto.Changeset.put_assoc(:entry_blocks, data_contained_datasource)
      |> Map.put(:action, :insert)

    {:ok, page_with_contained_datasource} = Brando.Pages.create_page(page_cs, user)

    page_cs =
      %Brando.Pages.Page{}
      |> Brando.Pages.Page.changeset(page_params, user)
      |> Ecto.Changeset.put_assoc(:entry_blocks, data_no_datasource)
      |> Map.put(:action, :insert)

    {:ok, page_with_no_datasource} = Brando.Pages.create_page(page_cs, user)

    found_ids =
      datasource_module
      |> Brando.Villain.list_block_ids_using_datamodule()
      |> Brando.Villain.list_root_block_ids_by_source()
      |> Brando.Villain.list_entry_ids_for_root_blocks_by_source()
      |> Map.get(schema)

    assert page_with_refed_datasource.id in found_ids
    assert page_with_contained_datasource.id in found_ids
    refute page_with_no_datasource.id in found_ids
  end
end
