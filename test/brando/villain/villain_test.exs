defmodule Brando.VillainTest do
  defmodule OtherParser do
    @behaviour Brando.Villain.Parser

    def text(%{text: _, type: _}, _), do: "other parser"
    def render_caption(_), do: ""
    def datatable(_, _), do: nil
    def datasource(_, _), do: nil
    def markdown(_, _), do: nil
    def input(_, _), do: nil
    def html(_, _), do: nil
    def svg(_, _), do: nil
    def table(_, _), do: nil
    def map(_, _), do: nil
    def blockquote(_, _), do: nil
    def columns(_, _), do: nil
    def divider(_, _), do: nil
    def header(_, _), do: nil
    def image(_, _), do: nil
    def media(_, _), do: nil
    def list(_, _), do: nil
    def slideshow(_, _), do: nil
    def gallery(_, _), do: nil
    def video(_, _), do: nil
    def module(_, _), do: nil
    def comment(_, _), do: nil
  end

  use ExUnit.Case, async: false
  use Brando.ConnCase
  alias Brando.Factory
  alias Brando.Villain

  setup do
    user = Factory.insert(:random_user)
    image = Factory.insert(:image, creator: user)

    {:ok, %{user: user, image: image}}
  end

  @data %{
    data: [
      %{
        type: "text",
        data: %{text: "**Some** text here.", type: "paragraph"}
      }
    ]
  }

  defp pf_data(text) do
    Factory.params_for(:fragment, %{
      parent_key: "blabla",
      key: "blabla",
      data: [
        %{
          type: "text",
          data: %{
            text: text,
            type: :paragraph
          }
        }
      ]
    })
  end

  test "parse" do
    Application.put_env(:brando, Brando.Villain, parser: Brando.Villain.ParserTest.Parser)

    assert Brando.Villain.parse("") == ""
    assert Brando.Villain.parse(nil) == ""

    assert Brando.Villain.parse([
             %{
               type: "text",
               data: %{text: "**Some** text here.", type: "paragraph"}
             }
           ]) == "**Some** text here."

    assert_raise FunctionClauseError, fn ->
      Brando.Villain.parse(%{text: "**Some** text here.", type: "paragraph"}) ==
        ""
    end
  end

  test "list_villains" do
    assert Enum.sort(Brando.Villain.list_villains()) == [
             {Brando.Content.Template,
              [%Brando.Blueprint.Attribute{name: :data, opts: %{}, type: :villain}]},
             {Brando.Pages.Fragment,
              [%Brando.Blueprint.Attribute{name: :data, opts: %{}, type: :villain}]},
             {Brando.Pages.Page,
              [%Brando.Blueprint.Attribute{name: :data, opts: %{}, type: :villain}]},
             {Brando.TraitTest.Project,
              [
                %Brando.Blueprint.Attribute{name: :bio_data, opts: %{}, type: :villain},
                %Brando.Blueprint.Attribute{name: :data, opts: %{}, type: :villain}
              ]}
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
                 formats: [:jpg],
                 src: "/media/image/1.jpg",
                 thumb: "/media/image/thumb/1.jpg",
                 title: "Title one",
                 width: 300,
                 dominant_color: nil,
                 alt: nil
               }
             ]
  end

  test "search_villains_for_text", %{user: user} do
    params = %{
      status: "published",
      parent_key: "parent_key",
      key: "key",
      language: "en",
      creator_id: user.id,
      data: [
        %{
          type: "text",
          data: %{text: "**Some** text here.", type: "paragraph"}
        }
      ]
    }

    params_empty_data = %{
      parent_key: "parent_key",
      key: "key",
      language: "en",
      creator_id: user.id,
      data: []
    }

    {:ok, pf1} = Brando.Pages.create_fragment(params, :system)

    _pf2 = Brando.Pages.create_fragment(params_empty_data, :system)
    _pf3 = Brando.Pages.create_fragment(params_empty_data, :system)

    {:ok, pf4} = Brando.Pages.create_fragment(params, :system)

    resulting_ids =
      Brando.Villain.search_villains_for_text(
        Brando.Pages.Fragment,
        :data,
        "text"
      )

    assert resulting_ids === [pf1.id, pf4.id]
  end

  test "search_villains_for_regex", %{user: user} do
    params = %{
      parent_key: "parent_key",
      key: "key",
      language: "en",
      status: "published",
      creator_id: user.id,
      data: [
        %{
          type: "text",
          data: %{
            text: "**Some** {{ globals.system.old }} here.",
            type: "paragraph"
          }
        }
      ]
    }

    params_empty_data = %{
      parent_key: "parent_key",
      key: "key",
      language: "en",
      creator_id: user.id,
      data: []
    }

    {:ok, pf1} = Brando.Pages.create_fragment(params, :system)

    _pf2 = Brando.Pages.create_fragment(params_empty_data, :system)
    _pf3 = Brando.Pages.create_fragment(params_empty_data, :system)

    {:ok, pf4} = Brando.Pages.create_fragment(params, :system)

    resulting_ids =
      Brando.Villain.search_villains_for_regex(
        Brando.Pages.Fragment,
        :data,
        globals: "{{ globals\.(.*?) }}"
      )

    assert resulting_ids === [pf1.id, pf4.id]
  end

  test "create and update dependent module", %{user: user} do
    module_params = %{
      code: "-- this is some code [{{ testvar }}] --",
      name: "Name",
      help_text: "Help text",
      refs: [],
      namespace: "all",
      class: "css class",
      vars: nil
    }

    {:ok, tp1} = Brando.Content.create_module(module_params, user)

    data = %{
      data: %{
        deleted_at: nil,
        module_id: tp1.id,
        multi: false,
        refs: [],
        sequence: 0,
        vars: [
          %{
            key: "testvar",
            label: "Field name",
            type: "text",
            value: "Some text!"
          }
        ]
      },
      type: "module"
    }

    {:ok, page} = Brando.Pages.create_page(Factory.params_for(:page, %{data: [data]}), user)

    assert page.html == "-- this is some code [Some text!] --"

    Brando.Content.update_module(
      tp1.id,
      %{code: "-- this is some NEW code [[{{ testvar }}]] --"},
      user
    )

    {:ok, updated_page} = Brando.Pages.get_page(page.id)
    assert updated_page.html == "-- this is some NEW code [[Some text!]] --"
  end

  test "update module ref will update entries using ref", %{user: user} do
    module_params = %{
      code: "{% ref refs.lede %}",
      name: "Name",
      help_text: "Help text",
      refs: [
        %{
          data: %{
            uid: "1wUr4ZLoOx53fqIslbP1dg",
            type: "text",
            hidden: false,
            data: %{
              text: "<p>A REF!</p>",
              extensions: nil,
              type: "lede"
            }
          },
          description: nil,
          name: "lede"
        }
      ],
      namespace: "all",
      class: "css class",
      vars: nil
    }

    {:ok, tp1} = Brando.Content.create_module(module_params, user)

    data = %{
      data: %{
        deleted_at: nil,
        module_id: tp1.id,
        multi: false,
        refs: [
          %{
            data: %{
              uid: "1wUr4ZLoOx53fqIslbP1dg",
              type: "text",
              hidden: false,
              data: %{
                text: "<p>A REF!</p>",
                extensions: nil,
                type: "lede"
              }
            },
            description: nil,
            name: "lede"
          }
        ],
        sequence: 0,
        vars: []
      },
      type: "module"
    }

    {:ok, page} = Brando.Pages.create_page(Factory.params_for(:page, %{data: [data]}), user)

    assert page.html == "<div class=\"lede\"><p>A REF!</p></div>"

    {:ok, _updated_module} =
      Brando.Content.update_module(
        tp1.id,
        %{
          refs: [
            %{
              data: %{
                uid: "1wUr4ZLoOx53fqIslbP1dg",
                type: "text",
                hidden: false,
                data: %{
                  text: "<p>A REFZZZ!</p>",
                  extensions: nil,
                  type: "paragraph"
                }
              },
              description: nil,
              name: "lede"
            }
          ]
        },
        user
      )

    {:ok, updated_page} = Brando.Pages.get_page(page.id)
    assert updated_page.html == "<div class=\"paragraph\"><p>A REF!</p></div>"
  end

  test "update module inside container", %{user: user} do
    module_params = %{
      code: "-- this is some code {{ testvar }} -- {% ref refs.lede %}",
      name: "Name",
      help_text: "Help text",
      refs: [
        %{
          data: %{
            uid: "1wUr4ZLoOx53fqIslbP1dg",
            type: "text",
            hidden: false,
            data: %{
              text: "<p>Lede</p>",
              extensions: nil,
              type: "lede"
            }
          },
          description: nil,
          name: "lede"
        }
      ],
      vars: [],
      namespace: "all",
      class: "css class"
    }

    {:ok, tp1} = Brando.Content.create_module(module_params, user)

    palette_params = %{
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

    data = [
      %{
        type: "container",
        data: %{
          palette_id: palette.id,
          blocks: [
            %{
              type: "module",
              data: %{
                module_id: tp1.id,
                multi: false,
                refs: [
                  %{
                    data: %{
                      uid: "1wUr4ZLoOx53fqIslbP1dg",
                      type: "text",
                      hidden: false,
                      data: %{
                        text: "<p>A REF!</p>",
                        extensions: nil,
                        type: "paragraph"
                      }
                    },
                    description: nil,
                    name: "lede"
                  }
                ],
                sequence: 0,
                vars: [
                  %{
                    key: "testvar",
                    label: "Field name",
                    type: "text",
                    value: "Some text!"
                  }
                ]
              }
            }
          ]
        }
      }
    ]

    params = Factory.params_for(:page, %{data: data}) |> Brando.Utils.map_from_struct()
    {:ok, page} = Brando.Pages.create_page(params, user)

    assert page.html ==
             "<section b-section=\"general-green\">\n  -- this is some code Some text! -- <div class=\"paragraph\"><p>A REF!</p></div>\n</section>\n"

    data = [
      %{
        type: "container",
        data: %{
          palette_id: palette.id,
          blocks: [
            %{
              type: "module",
              data: %{
                deleted_at: nil,
                module_id: tp1.id,
                multi: false,
                refs: [
                  %{
                    data: %{
                      uid: "1wUr4ZLoOx53fqIslbP1dg",
                      type: "text",
                      hidden: false,
                      data: %{
                        text: "<p>A REF!</p>",
                        extensions: nil,
                        type: "paragraph"
                      }
                    },
                    description: nil,
                    name: "lede"
                  }
                ],
                sequence: 0,
                vars: [
                  %{
                    key: "testvar",
                    label: "Field name",
                    type: "text",
                    value: "Some text!"
                  }
                ]
              }
            }
          ]
        }
      }
    ]

    params = Factory.params_for(:page, %{data: data}) |> Brando.Utils.map_from_struct()
    {:ok, page2} = Brando.Pages.create_page(params, user)

    assert page2.html ==
             "<section b-section=\"general-green\">\n  -- this is some code Some text! -- <div class=\"paragraph\"><p>A REF!</p></div>\n</section>\n"

    tp2 =
      tp1
      |> Map.put(:code, "-- this is some NEW code {{ testvar }} -- {% ref refs.lede %}")
      |> Map.put(:refs, [
        %{
          data: %{
            uid: "1wUr4ZLoOx53fqIslbP1dg",
            type: "text",
            hidden: false,
            data: %{
              text: "<p>A REFZZZ!</p>",
              extensions: nil,
              type: "lede"
            }
          },
          description: nil,
          name: "lede"
        }
      ])
      |> Map.from_struct()
      |> Brando.Utils.stringify_keys()

    Brando.Content.update_module(tp1.id, tp2, user)

    {:ok, updated_page} = Brando.Pages.get_page(page.id)

    assert updated_page.html ==
             "<section b-section=\"general-green\">\n  -- this is some NEW code Some text! -- <div class=\"lede\"><p>A REF!</p></div>\n</section>\n"
  end

  test "access refs in context", %{user: user} do
    module_params = %{
      code: "A variable: {{ testvar }} -- A ref: {% ref refs.lede %}",
      name: "Name",
      help_text: "Help text",
      refs: [],
      namespace: "all",
      class: "css class"
    }

    {:ok, tp1} = Brando.Content.create_module(module_params, user)

    data = %{
      data: %{
        deleted_at: nil,
        module_id: tp1.id,
        multi: false,
        refs: [
          %{
            data: %{
              uid: "1wUr4ZLoOx53fqIslbP1dg",
              type: "text",
              hidden: false,
              data: %{
                text: "<p>A REF!</p>",
                extensions: nil,
                type: "lede"
              }
            },
            description: nil,
            name: "lede"
          }
        ],
        sequence: 0,
        vars: [
          %{
            key: "testvar",
            label: "Field name",
            type: "text",
            value: "VARIABLE!"
          }
        ]
      },
      type: "module"
    }

    {:ok, page} = Brando.Pages.create_page(Factory.params_for(:page, %{data: [data]}), user)

    assert page.html == "A variable: VARIABLE! -- A ref: <div class=\"lede\"><p>A REF!</p></div>"
  end

  test "headless refs are ignored", %{user: user} do
    module_params = %{
      code: "A variable: {{ testvar }} -- A ref:{% headless_ref refs.lede %}",
      name: "Name",
      help_text: "Help text",
      refs: [],
      namespace: "all",
      class: "css class"
    }

    {:ok, tp1} = Brando.Content.create_module(module_params, user)

    data = %{
      data: %{
        deleted_at: nil,
        module_id: tp1.id,
        multi: false,
        refs: [
          %{
            data: %{
              uid: "1wUr4ZLoOx53fqIslbP1dg",
              type: "text",
              hidden: false,
              data: %{
                text: "<p>A REF!</p>",
                extensions: nil,
                type: "lede"
              }
            },
            description: nil,
            name: "lede"
          }
        ],
        sequence: 0,
        vars: [
          %{
            key: "testvar",
            label: "Field name",
            type: "text",
            value: "VARIABLE!"
          }
        ]
      },
      type: "module"
    }

    {:ok, page} = Brando.Pages.create_page(Factory.params_for(:page, %{data: [data]}), user)

    assert page.html == "A variable: VARIABLE! -- A ref:"
  end

  test "rerender_villains_for", %{user: user} do
    {:ok, _} =
      Brando.Pages.create_page(
        Map.merge(@data, %{
          status: :published,
          creator_id: user.id,
          title: "a",
          uri: "a",
          template: "template.html",
          language: "en"
        }),
        :system
      )

    {:ok, _} =
      Brando.Pages.create_page(
        Map.merge(@data, %{
          status: :published,
          creator_id: user.id,
          title: "a",
          uri: "a",
          template: "template.html",
          language: "en"
        }),
        :system
      )

    {:ok, _} =
      Brando.Pages.create_page(
        Map.merge(@data, %{
          status: :published,
          creator_id: user.id,
          title: "a",
          uri: "a",
          template: "template.html",
          language: "en"
        }),
        :system
      )

    result = Brando.Villain.rerender_villains_for(Brando.Pages.Page)

    assert result |> List.flatten() |> Keyword.keys() |> Enum.count() == 3
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
    {:ok, pf1} = Brando.Pages.create_fragment(pf_params, user)

    Brando.Cache.Navigation.set()
    {:ok, _menu} = Brando.Navigation.update_menu(menu.id, %{title: "New title"}, user)

    pf2 = Brando.repo().get(Brando.Pages.Fragment, pf1.id)
    assert pf2.html == "<div class=\"paragraph\">**Some** New title here.</div>"
  end

  test "ensure villains update on globals changes", %{user: user} do
    Brando.Cache.Globals.set()

    global_set_params = %{
      label: "System",
      key: "system",
      language: "en",
      globals: [
        %{type: "text", label: "Text", key: "text", value: "My text"}
      ]
    }

    global_set_params_no = %{
      label: "System",
      key: "system",
      language: "no",
      globals: [
        %{type: "text", label: "Text", key: "text", value: "Min tekst"}
      ]
    }

    pf_params = pf_data("So the global says: '{{ globals.system.text }}'.")

    {:ok, gc1} = Brando.Sites.create_global_set(global_set_params, user)
    {:ok, _} = Brando.Sites.create_global_set(global_set_params_no, user)
    {:ok, pf1} = Brando.Pages.create_fragment(pf_params, user)
    {:ok, pf2} = Brando.Pages.create_fragment(Map.put(pf_params, :language, "no"), user)

    assert pf1.html == "<div class=\"paragraph\">So the global says: 'My text'.</div>"
    assert pf2.html == "<div class=\"paragraph\">So the global says: 'Min tekst'.</div>"

    Brando.Sites.update_global_set(
      gc1.id,
      %{
        globals: [
          %{type: "text", label: "Text", key: "text", value: "My replaced text"}
        ]
      },
      :system
    )

    pf2 = Brando.repo().get(Brando.Pages.Fragment, pf1.id)

    assert pf2.html == "<div class=\"paragraph\">So the global says: 'My replaced text'.</div>"
  end

  test "ensure villains update on identity changes", %{user: user} do
    Brando.Cache.Identity.set()

    pf_params = pf_data("So identity.name says: '{{ identity.name }}'.")

    {:ok, pf1} = Brando.Pages.create_fragment(pf_params, user)

    assert pf1.html ==
             "<div class=\"paragraph\">So identity.name says: 'Organization name'.</div>"

    {:ok, identity} = Brando.Sites.get_identity(%{matches: %{language: "en"}})
    Brando.Sites.update_identity(identity, %{name: "Eddie Hazel Inc"}, user)

    pf2 = Brando.repo().get(Brando.Pages.Fragment, pf1.id)
    assert pf2.html == "<div class=\"paragraph\">So identity.name says: 'Eddie Hazel Inc'.</div>"
  end

  test "ensure villains update on link changes", %{user: user} do
    Brando.Cache.Identity.set()

    pf_params = pf_data("So links.instagram.url says: '{{ links.instagram.url }}'.")

    {:ok, pf1} = Brando.Pages.create_fragment(pf_params, user)

    assert pf1.html ==
             "<div class=\"paragraph\">So links.instagram.url says: 'https://instagram.com/test'.</div>"

    {:ok, identity} = Brando.Sites.get_identity(%{matches: %{language: "en"}})

    Brando.Sites.update_identity(
      identity,
      %{links: [%{name: "Instagram", url: "https://instagram.com"}]},
      user
    )

    pf2 = Brando.repo().get(Brando.Pages.Fragment, pf1.id)

    assert pf2.html ==
             "<div class=\"paragraph\">So links.instagram.url says: 'https://instagram.com'.</div>"

    {:ok, identity} = Brando.Sites.get_identity(%{matches: %{language: "en"}})

    Brando.Sites.update_identity(
      identity,
      %{
        links: [
          %{name: "Instagram", url: "https://instagram.com/test"},
          %{name: "Facebook", url: "https://facebook.com/test"}
        ]
      },
      user
    )
  end

  test "ensure villains update on config changes", %{user: user} do
    Brando.Cache.Identity.set()

    pf_params = pf_data("So configs.key1.value says: '{{ configs.key1.value }}'.")

    {:ok, pf1} = Brando.Pages.create_fragment(pf_params, user)
    assert pf1.html == "<div class=\"paragraph\">So configs.key1.value says: 'value1'.</div>"

    {:ok, identity} = Brando.Sites.get_identity(%{matches: %{language: "en"}})

    Brando.Sites.update_identity(
      identity,
      %{configs: [%{key: "key1", value: "wow!"}]},
      user
    )

    pf2 = Brando.repo().get(Brando.Pages.Fragment, pf1.id)
    assert pf2.html == "<div class=\"paragraph\">So configs.key1.value says: 'wow!'.</div>"
  end

  test "fragment tag", %{user: user} do
    pf_params1 =
      Factory.params_for(:fragment, %{
        parent_key: "parent_test",
        key: "frag_key",
        data: [
          %{
            type: "html",
            data: %{
              text: "Hello from the fragment!"
            }
          }
        ]
      })

    pf_params2 =
      Factory.params_for(:fragment, %{
        parent_key: "parent_test",
        key: "test_key",
        data: [
          %{
            type: "html",
            data: %{
              text: "--> {% fragment parent_test frag_key en %} <--"
            }
          }
        ]
      })

    pf_params3 =
      Factory.params_for(:fragment, %{
        parent_key: "parent_test",
        key: "test_key",
        data: [
          %{
            type: "html",
            data: %{
              text: "--> {% hide %}parent_test{% endhide %} <--"
            }
          }
        ]
      })

    {:ok, pf1} = Brando.Pages.create_fragment(pf_params1, user)
    {:ok, pf2} = Brando.Pages.create_fragment(pf_params2, user)
    {:ok, pf3} = Brando.Pages.create_fragment(pf_params3, user)

    assert pf1.html == "Hello from the fragment!"
    assert pf2.html == "--> Hello from the fragment! <--"
    assert pf3.html == "--> parent_test <--"
  end

  test "search modules for regex" do
    ExMachina.Sequence.reset()

    _tp1 =
      Factory.insert(:module, %{
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
      Factory.insert(:module, %{
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

    [r1, r2] = Villain.search_modules_for_regex(search_terms)

    assert r1["name"] == "Old style"
    assert r1["old_for_loops"] == ["{% for test <- old_style %}"]
    assert r1["old_vars"] == ["${globals:old.varstyle}"]

    assert r2["name"] == "Old style"
    assert r2["old_for_loops"] == nil
    assert r2["old_vars"] == ["${testoldvar}"]
  end

  test "render template locale by entry's language", %{user: user} do
    pf_params =
      pf_data("""
      {% if locale == "en" %}
        ENGLISH
      {% else %}
        NORWEGIAN
      {% endif %}
      """)
      |> Map.put(:language, "en")

    {:ok, pf1} = Brando.Pages.create_fragment(pf_params, user)
    assert pf1.html == "<div class=\"paragraph\">\n  ENGLISH\n\n</div>"

    {:ok, pf2} = Brando.Pages.update_fragment(pf1, %{"language" => "no"}, user)
    assert pf2.html == "<div class=\"paragraph\">\n  NORWEGIAN\n\n</div>"
  end
end
