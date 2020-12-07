defmodule Brando.VillainTest do
  defmodule OtherParser do
    @behaviour Brando.Villain.Parser

    def text(%{"text" => _, "type" => _}, _), do: "other parser"
    def render_caption(_), do: ""
    def datatable(_, _), do: nil
    def datasource(_, _), do: nil
    def markdown(_, _), do: nil
    def input(_, _), do: nil
    def html(_, _), do: nil
    def svg(_, _), do: nil
    def map(_, _), do: nil
    def blockquote(_, _), do: nil
    def columns(_, _), do: nil
    def divider(_, _), do: nil
    def header(_, _), do: nil
    def image(_, _), do: nil
    def media(_, _), do: nil
    def list(_, _), do: nil
    def slideshow(_, _), do: nil
    def video(_, _), do: nil
    def template(_, _), do: nil
    def comment(_, _), do: nil
  end

  use ExUnit.Case
  use Brando.ConnCase
  alias Brando.Factory
  alias Brando.Villain

  setup do
    user = Factory.insert(:random_user)
    category = Factory.insert(:image_category, creator: user)
    series = Factory.insert(:image_series, creator: user, image_category: category)
    image = Factory.insert(:image, creator: user, image_series: series)

    {:ok, %{user: user, category: category, series: series, image: image}}
  end

  @data %{
    data: [
      %{
        "type" => "text",
        "data" => %{"text" => "**Some** text here.", "type" => "paragraph"}
      }
    ]
  }

  defp pf_data(text) do
    Factory.params_for(:page_fragment, %{
      parent_key: "blabla",
      key: "blabla",
      data: [
        %{
          "type" => "text",
          "data" => %{
            "text" => text,
            "type" => "paragraph"
          }
        }
      ]
    })
  end

  test "parse" do
    Application.put_env(:brando, Brando.Villain, parser: Brando.Villain.ParserTest.Parser)

    assert Brando.Villain.parse("") == ""
    assert Brando.Villain.parse(nil) == ""

    assert Brando.Villain.parse(
             ~s([{"type":"columns","data":[{"class":"col-md-6 six","data":[]},{"class":"col-md-6 six","data":[{"type":"markdown","data":{"text":"Markdown"}}]}]}])
           ) ==
             "<div class=\"row\"><div class=\"col-md-6 six\"></div><div class=\"col-md-6 six\"><p>Markdown</p></div></div>"

    assert Brando.Villain.parse([
             %{
               "type" => "text",
               "data" => %{"text" => "**Some** text here.", "type" => "paragraph"}
             }
           ]) == "<p><strong>Some</strong> text here.</p>"

    assert_raise FunctionClauseError, fn ->
      Brando.Villain.parse(%{"text" => "**Some** text here.", "type" => "paragraph"}) ==
        ""
    end
  end

  test "list_villains" do
    assert Brando.Villain.list_villains() == [
             {Brando.Pages.Page, [{:villain, :data, :html}]},
             {Brando.Pages.PageFragment, [{:villain, :data, :html}]}
           ]
  end

  test "map_images", %{image: image} do
    mapped_images =
      [image]
      |> Brando.Villain.map_images()
      |> Enum.map(&Map.delete(&1, :inserted_at))

    assert mapped_images ==
             [
               %{
                 credits: "Credits",
                 height: 292,
                 sizes: %{
                   "large" => "/media/image/large/1.jpg",
                   "medium" => "/media/image/medium/1.jpg",
                   "small" => "/media/image/small/1.jpg",
                   "thumb" => "/media/image/thumb/1.jpg",
                   "xlarge" => "/media/image/xlarge/1.jpg"
                 },
                 src: "/media/image/1.jpg",
                 thumb: "/media/image/thumb/1.jpg",
                 title: "Title one",
                 width: 300,
                 webp: false
               }
             ]
  end

  test "search_villains_for_text" do
    pf1 =
      Factory.insert(:page_fragment, %{
        data: [
          %{
            "type" => "text",
            "data" => %{"text" => "**Some** text here.", "type" => "paragraph"}
          }
        ]
      })

    _pf2 = Factory.insert(:page_fragment, %{data: []})
    _pf3 = Factory.insert(:page_fragment, %{data: []})

    pf4 =
      Factory.insert(:page_fragment, %{
        data: [
          %{
            "type" => "text",
            "data" => %{"text" => "**Some** text here.", "type" => "paragraph"}
          }
        ]
      })

    resulting_ids =
      Brando.Villain.search_villains_for_text(
        Brando.Pages.PageFragment,
        :data,
        "text"
      )

    assert resulting_ids === [pf1.id, pf4.id]
  end

  test "search_villains_for_regex" do
    pf1 =
      Factory.insert(:page_fragment, %{
        data: [
          %{
            "type" => "text",
            "data" => %{
              "text" => "**Some** {{ globals.system.old }} here.",
              "type" => "paragraph"
            }
          }
        ]
      })

    _pf2 = Factory.insert(:page_fragment, %{data: []})

    _pf3 =
      Factory.insert(:page_fragment, %{
        data: [
          %{
            "type" => "text",
            "data" => %{"text" => "**Some** {{ glob.system.old }} here.", "type" => "paragraph"}
          }
        ]
      })

    pf4 =
      Factory.insert(:page_fragment, %{
        data: [
          %{
            "type" => "text",
            "data" => %{
              "text" => "**Some** {{ globals.system.old }} here.",
              "type" => "paragraph"
            }
          }
        ]
      })

    resulting_ids =
      Brando.Villain.search_villains_for_regex(
        Brando.Pages.PageFragment,
        :data,
        globals: "{{ globals\.(.*?) }}"
      )

    assert resulting_ids === [pf1.id, pf4.id]
  end

  test "create and update dependent template", %{user: user} do
    tp1 =
      Factory.insert(:template, %{
        code: "-- this is some code {{ testvar }} --",
        name: "Name",
        help_text: "Help text",
        refs: [],
        namespace: "all",
        class: "css class"
      })

    data = %{
      "data" => %{
        "deleted_at" => nil,
        "id" => tp1.id,
        "multi" => false,
        "refs" => [],
        "sequence" => 0,
        "vars" => %{
          "testvar" => %{
            "label" => "Field name",
            "type" => "text",
            "value" => "Some text!"
          }
        }
      },
      "type" => "template"
    }

    {:ok, page} = Brando.Pages.create_page(Factory.params_for(:page, %{data: [data]}), user)

    assert page.html == "-- this is some code Some text! --"

    tp2 =
      tp1
      |> Map.put(:code, "-- this is some NEW code {{ testvar }} --")
      |> Map.from_struct()
      |> Brando.Utils.stringify_keys()

    Brando.Villain.update_template(tp1.id, tp2)

    {:ok, updated_page} = Brando.Pages.get_page(page.id)
    assert updated_page.html == "-- this is some NEW code Some text! --"
  end

  test "rerender_villains_for" do
    _p1 = Factory.insert(:page, @data)
    _p2 = Factory.insert(:page, @data)
    _p3 = Factory.insert(:page, @data)

    result = Brando.Villain.rerender_villains_for(Brando.Pages.Page)

    assert result |> List.flatten() |> Keyword.keys() |> Enum.count() == 3
  end

  test "get_cached_template" do
    tp1 =
      Factory.insert(:template, %{
        code: "-- this is some code {{ testvar }} --",
        name: "Name",
        help_text: "Help text",
        refs: [],
        namespace: "all",
        class: "css class"
      })

    {:ok, template} = Brando.Villain.get_cached_template(tp1.id)
    assert template.id == tp1.id

    {:ok, template} = Brando.Villain.get_cached_template(tp1.id)
    assert template.id == tp1.id
  end

  test "ensure villains update on navigation changes", %{user: user} do
    {:ok, menu} =
      Brando.Navigation.create_menu(
        %{
          status: :published,
          title: "Title",
          key: "main",
          language: "en",
          items: []
        },
        user
      )

    pf_params = pf_data("**Some** {{ navigation.main.en.title }} here.")
    {:ok, pf1} = Brando.Pages.create_page_fragment(pf_params, user)

    Brando.Cache.Navigation.set()
    {:ok, _menu} = Brando.Navigation.update_menu(menu.id, %{title: "New title"}, user)

    pf2 = Brando.repo().get(Brando.Pages.PageFragment, pf1.id)
    assert pf2.html == "<p><strong>Some</strong> New title here.</p>"
  end

  test "ensure villains update on globals changes", %{user: user} do
    Brando.Cache.Globals.set()

    global_category_params = %{
      "label" => "System",
      "key" => "system",
      "globals" => [
        %{type: "text", label: "Text", key: "text", data: %{"value" => "My text"}}
      ]
    }

    pf_params = pf_data("So the global says: '{{ globals.system.text }}'.")

    {:ok, gc1} = Brando.Globals.create_global_category(global_category_params)
    {:ok, pf1} = Brando.Pages.create_page_fragment(pf_params, user)

    assert pf1.html == "<p>So the global says: ‘My text’.</p>"

    Brando.Globals.update_global_category(gc1.id, %{
      "globals" => [
        %{type: "text", label: "Text", key: "text", data: %{"value" => "My replaced text"}}
      ]
    })

    pf2 = Brando.repo().get(Brando.Pages.PageFragment, pf1.id)

    assert pf2.html == "<p>So the global says: ‘My replaced text’.</p>"
  end

  test "ensure villains update on identity changes", %{user: user} do
    Brando.Cache.Identity.set()

    pf_params = pf_data("So identity.name says: '{{ identity.name }}'.")

    {:ok, pf1} = Brando.Pages.create_page_fragment(pf_params, user)
    assert pf1.html == "<p>So identity.name says: ‘Organisasjonens navn’.</p>"

    Brando.Sites.update_identity(%{"name" => "Eddie Hazel Inc"}, user)

    pf2 = Brando.repo().get(Brando.Pages.PageFragment, pf1.id)
    assert pf2.html == "<p>So identity.name says: ‘Eddie Hazel Inc’.</p>"
  end

  test "ensure villains update on link changes", %{user: user} do
    Brando.Cache.Identity.set()

    pf_params = pf_data("So links.instagram.url says: '{{ links.instagram.url }}'.")

    {:ok, pf1} = Brando.Pages.create_page_fragment(pf_params, user)
    assert pf1.html == "<p>So links.instagram.url says: ‘https://instagram.com/test’.</p>"

    Brando.Sites.update_identity(
      %{"links" => [%{"name" => "Instagram", "url" => "https://instagram.com"}]},
      user
    )

    pf2 = Brando.repo().get(Brando.Pages.PageFragment, pf1.id)
    assert pf2.html == "<p>So links.instagram.url says: ‘https://instagram.com’.</p>"
  end

  test "ensure villains update on config changes", %{user: user} do
    Brando.Cache.Identity.set()

    pf_params = pf_data("So configs.key1.value says: '{{ configs.key1.value }}'.")

    {:ok, pf1} = Brando.Pages.create_page_fragment(pf_params, user)
    assert pf1.html == "<p>So configs.key1.value says: ‘value1’.</p>"

    Brando.Sites.update_identity(
      %{"configs" => [%{"key" => "key1", "value" => "wow!"}]},
      user
    )

    pf2 = Brando.repo().get(Brando.Pages.PageFragment, pf1.id)
    assert pf2.html == "<p>So configs.key1.value says: ‘wow!’.</p>"
  end

  test "fragment tag", %{user: user} do
    pf_params1 =
      Factory.params_for(:page_fragment, %{
        parent_key: "parent_test",
        key: "frag_key",
        data: [
          %{
            "type" => "html",
            "data" => %{
              "text" => "Hello from the fragment!"
            }
          }
        ]
      })

    pf_params2 =
      Factory.params_for(:page_fragment, %{
        parent_key: "parent_test",
        key: "test_key",
        data: [
          %{
            "type" => "html",
            "data" => %{
              "text" => "--> {% fragment parent_test frag_key en %} <--"
            }
          }
        ]
      })

    {:ok, pf1} = Brando.Pages.create_page_fragment(pf_params1, user)
    {:ok, pf2} = Brando.Pages.create_page_fragment(pf_params2, user)

    assert pf1.html == "Hello from the fragment!"
    assert pf2.html == "--> Hello from the fragment! <--"
  end

  test "search templates for regex" do
    ExMachina.Sequence.reset()

    _tp1 =
      Factory.insert(:template, %{
        code: """
        this is some code ${globals:old.varstyle}, ${testoldvar}
        {% for test <- old_style %}
          blip
        {% end %}
        """,
        name: "Old style",
        help_text: "Help text",
        refs: [],
        namespace: "Namespace",
        class: "css class"
      })

    _tp2 =
      Factory.insert(:template, %{
        code: """
        {{ new_style }}
        {% for test in bla %}
          hello
        {% end %}
        """,
        name: "New style",
        help_text: "Help text",
        refs: [],
        namespace: "Namespace",
        class: "css class"
      })

    search_terms = [old_vars: "\\${.*?}", old_for_loops: "{\\% for .*? <- .*? \\%}"]

    [r1, r2] = Villain.search_templates_for_regex(search_terms)

    assert r1["name"] == "Old style"
    assert r1["old_for_loops"] == ["{% for test <- old_style %}"]
    assert r1["old_vars"] == ["${globals:old.varstyle}"]

    assert r2["name"] == "Old style"
    assert r2["old_for_loops"] == nil
    assert r2["old_vars"] == ["${testoldvar}"]
  end
end
