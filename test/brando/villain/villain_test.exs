defmodule Brando.VillainTest do
  defmodule OtherParser do
    @behaviour Brando.Villain.Parser

    def text(%{text: _, type: _}, _), do: "other parser"
    def render_caption(_), do: ""
    def video_file_options(_), do: []
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

  defp pf_cs(text) do
    module_params = Factory.params_for(:module, %{code: "{% ref refs.text %}"})
    {:ok, module} = Brando.Content.create_module(module_params, :system)

    params =
      Factory.params_for(:fragment, %{
        parent_key: "blabla",
        key: "blabla",
        entry_blocks: [
          %{
            block: %{
              type: :module,
              source: "Elixir.Brando.Pages.Fragment.Blocks",
              module_id: module.id,
              refs: [
                %{
                  name: "text",
                  data: %Brando.Villain.Blocks.TextBlock{
                    uid: "1wUr4ZLoOx53fqIslbP1dg",
                    data: %Brando.Villain.Blocks.TextBlock.Data{
                      text: text,
                      type: :paragraph
                    }
                  }
                }
              ]
            }
          }
        ]
      })

    %Brando.Pages.Fragment{}
    |> Ecto.Changeset.change(params)
  end

  test "parse" do
    Application.put_env(:brando, Brando.Villain, parser: Brando.Villain.ParserTest.Parser)

    assert Brando.Villain.parse("") == ""
    assert Brando.Villain.parse(nil) == ""

    # TODO: Test with module blocks, containers / multi blocks

    # assert Brando.Villain.parse([
    #          %{
    #            block: %{
    #              type: :text,
    #              data: %{text: "**Some** text here.", type: "paragraph"}
    #            }
    #          }
    #        ]) == "**Some** text here."

    # assert_raise FunctionClauseError, fn ->
    #   Brando.Villain.parse(%{text: "**Some** text here.", type: "paragraph"}) ==
    #     ""
    # end

    # conn = %{request_path: "/projects/all", path_params: %{"category_slug" => "all"}}

    # assert Brando.Villain.parse(
    #          [
    #            %{
    #              type: "text",
    #              data: %{
    #                text: "The url is {{ request.url }}. Param: {{ request.params.category_slug }}"
    #              }
    #            }
    #          ],
    #          nil,
    #          conn: conn
    #        ) ==
    #          "The url is /projects/all. Param: all"
  end

  test "list_blocks" do
    assert Enum.sort(Brando.Villain.list_blocks()) == [
             {Brando.Content.Template,
              [
                %Brando.Blueprint.Relation{
                  name: :blocks,
                  opts: %{module: :blocks},
                  type: :has_many
                }
              ]},
             {Brando.Pages.Fragment,
              [
                %Brando.Blueprint.Relation{
                  name: :blocks,
                  opts: %{module: :blocks},
                  type: :has_many
                }
              ]},
             {Brando.Pages.Page,
              [
                %Brando.Blueprint.Relation{
                  name: :blocks,
                  opts: %{module: :blocks},
                  type: :has_many
                }
              ]},
             {Brando.TraitTest.Project,
              [
                %Brando.Blueprint.Relation{
                  name: :blocks,
                  opts: %{module: :blocks},
                  type: :has_many
                },
                %Brando.Blueprint.Relation{
                  name: :bio_blocks,
                  opts: %{module: :blocks},
                  type: :has_many
                }
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

  test "list_block_ids_matching_regex", %{user: user} do
    text_ref = %Brando.Content.Module.Ref{
      data: %Brando.Villain.Blocks.TextBlock{
        uid: "1wUr4ZLoOx53fqIslbP1dg",
        active: true,
        data: %Brando.Villain.Blocks.TextBlock.Data{
          text: "<p>{{ globals.site.name }}</p>",
          extensions: nil,
          type: "paragraph"
        }
      },
      description: nil,
      name: "text"
    }

    # insert module
    module_params = %Brando.Content.Module{
      code: "{% ref refs.text %}",
      name: "Name",
      help_text: "Help text",
      refs: [
        text_ref
      ],
      namespace: "all",
      class: "css class",
      vars: []
    }

    {:ok, module} = Brando.repo().insert(module_params)

    simple_blocks = [
      %Brando.Pages.Fragment.Blocks{
        block: %Brando.Content.Block{
          type: :module,
          source: "Elixir.Brando.Pages.Fragment.Blocks",
          module_id: module.id,
          uid: "1wUr4ZLoOx53fqIslbP1dg",
          refs: [
            text_ref
          ],
          vars: []
        }
      }
      |> Ecto.Changeset.change()
      |> Map.put(:action, :insert)
    ]

    fragment_params = Factory.params_for(:fragment)

    fragment_cs = Brando.Pages.Fragment.changeset(%Brando.Pages.Fragment{}, fragment_params, user)
    fragment_cs = Ecto.Changeset.put_assoc(fragment_cs, :entry_blocks, simple_blocks)
    fragment_cs = Map.put(fragment_cs, :action, :insert)

    params_empty_data = %{
      parent_key: "parent_key",
      key: "key",
      language: "en",
      creator_id: user.id,
      entry_blocks: []
    }

    {:ok, pf1} = Brando.Pages.create_fragment(fragment_cs, user)
    _pf2 = Brando.Pages.create_fragment(params_empty_data, user)
    _pf3 = Brando.Pages.create_fragment(params_empty_data, user)
    {:ok, pf4} = Brando.Pages.create_fragment(fragment_cs, user)

    resulting_ids =
      Brando.Villain.list_block_ids_matching_regex(globals: "{{ globals\.(.*?) }}")
      |> Brando.Villain.list_root_block_ids_by_source()
      |> Brando.Villain.list_entry_ids_for_root_blocks_by_source()

    # sort the ids
    sorted_resulting_ids =
      resulting_ids
      |> Enum.map(fn {k, v} -> {k, Enum.sort(v)} end)
      |> Enum.into(%{})

    assert sorted_resulting_ids === %{Brando.Pages.Fragment => [pf1.id, pf4.id]}
  end

  test "create and update dependent module", %{user: user} do
    module_params =
      Factory.params_for(:module, %{
        code: "-- this is some code [{{ testvar }}] --",
        name: "Name",
        help_text: "Help text",
        refs: [],
        namespace: "all",
        class: "css class",
        vars: []
      })

    {:ok, module} = Brando.Content.create_module(module_params, user)
    params = Factory.params_for(:page, creator_id: user.id)

    cs =
      %Brando.Pages.Page{}
      |> Ecto.Changeset.change(params)
      |> Ecto.Changeset.put_assoc(:entry_blocks, [
        %{
          block: %{
            module_id: module.id,
            multi: false,
            refs: [],
            sequence: 0,
            source: "Elixir.Brando.Pages.Page.Blocks",
            vars: [
              %{
                key: "testvar",
                label: "Field name",
                type: :text,
                value: "Some text!"
              }
            ],
            type: :module
          }
        }
      ])

    {:ok, page} = Brando.Pages.create_page(cs, user)
    {:ok, page} = Brando.Villain.render_entry(Brando.Pages.Page, page.id)

    assert page.rendered_blocks == "-- this is some code [Some text!] --"

    Brando.Content.update_module(
      module.id,
      %{code: "-- this is some NEW code [[{{ testvar }}]] --"},
      user
    )

    {:ok, updated_page} = Brando.Pages.get_page(page.id)
    assert updated_page.rendered_blocks == "-- this is some NEW code [[Some text!]] --"
  end

  test "update module ref will update entries using ref", %{user: user} do
    module_params = %Brando.Content.Module{
      code: "{% ref refs.lede %}",
      name: "Name",
      help_text: "Help text",
      refs: [
        %Brando.Content.Module.Ref{
          data: %Brando.Villain.Blocks.TextBlock{
            uid: "1wUr4ZLoOx53fqIslbP1dg",
            type: "text",
            active: true,
            data: %Brando.Villain.Blocks.TextBlock.Data{
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
      vars: []
    }

    {:ok, tp1} = Brando.repo().insert(module_params)

    simple_blocks = [
      %Brando.Pages.Page.Blocks{
        block: %Brando.Content.Block{
          type: :module,
          source: "Elixir.Brando.Pages.Page.Blocks",
          module_id: tp1.id,
          uid: "1wUr4ZLoOx53fqIslbP1dg",
          refs: [
            %{
              data: %Brando.Villain.Blocks.TextBlock{
                uid: "1wUr4ZLoOx53fqIslbP1dg",
                type: "text",
                active: true,
                data: %Brando.Villain.Blocks.TextBlock.Data{
                  text: "<p>A REF!</p>",
                  extensions: nil,
                  type: "lede"
                }
              },
              description: nil,
              name: "lede"
            }
          ],
          vars: []
        }
      }
    ]

    page_params = Factory.params_for(:page, %{creator_id: user.id})

    page_cs = Brando.Pages.Page.changeset(%Brando.Pages.Page{}, page_params, user)
    page_cs = Ecto.Changeset.put_assoc(page_cs, :entry_blocks, simple_blocks)
    page_cs = Map.put(page_cs, :action, :insert)

    {:ok, page} = Brando.Pages.create_page(page_cs, user)
    {:ok, page} = Brando.Villain.render_entry(Brando.Pages.Page, page.id)

    assert page.rendered_blocks == "<div class=\"lede\"><p>A REF!</p></div>"

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
    assert updated_page.rendered_blocks == "<div class=\"paragraph\"><p>A REF!</p></div>"
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
            active: true,
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

    simple_blocks = [
      %{
        block: %{
          type: :container,
          uid: "container-a1",
          source: "Elixir.Brando.Pages.Page.Blocks",
          palette_id: palette.id,
          children: [
            %{
              type: :module,
              module_id: tp1.id,
              source: "Elixir.Brando.Pages.Page.Blocks",
              multi: false,
              refs: [
                %{
                  data: %Brando.Villain.Blocks.TextBlock{
                    uid: "1wUr4ZLoOx53fqIslbP1dg",
                    type: "text",
                    active: true,
                    data: %Brando.Villain.Blocks.TextBlock.Data{
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
                  type: :text,
                  value: "Some text!"
                }
              ]
            }
          ]
        }
      }
    ]

    page_params = Factory.params_for(:page)
    page_cs = Brando.Pages.Page.changeset(%Brando.Pages.Page{}, page_params, user)
    page_cs = Ecto.Changeset.put_assoc(page_cs, :entry_blocks, simple_blocks)
    page_cs = Map.put(page_cs, :action, :insert)
    {:ok, page} = Brando.Pages.create_page(page_cs, user)
    {:ok, page} = Brando.Villain.render_entry(Brando.Pages.Page, page.id)

    assert page.rendered_blocks ==
             "<section b-section=\"general-green\">\n  <!-- {+:C<container-a1>} -->\n  -- this is some code Some text! -- <div class=\"paragraph\"><p>A REF!</p></div>\n<!-- {-:C<container-a1>} -->\n\n</section>\n"

    module2_params = %{
      code: "-- this is some NEW code {{ testvar }} -- {% ref refs.lede %}",
      name: "Name",
      help_text: "Help text",
      refs: [
        %{
          data: %{
            uid: "1wUr4ZLoOx53fqIslbP1dg",
            type: "text",
            active: true,
            data: %{
              text: "<p>NEW REF</p>",
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

    Brando.Content.update_module(tp1.id, module2_params, user)

    {:ok, updated_page} = Brando.Pages.get_page(page.id)

    assert updated_page.rendered_blocks ==
             "<section b-section=\"general-green\">\n  <!-- {+:C<container-a1>} -->\n  -- this is some NEW code Some text! -- <div class=\"lede\"><p>A REF!</p></div>\n<!-- {-:C<container-a1>} -->\n\n</section>\n"
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

    simple_blocks = [
      %{
        block: %{
          type: :module,
          module_id: tp1.id,
          source: "Elixir.Brando.Pages.Page.Blocks",
          multi: false,
          refs: [
            %{
              data: %Brando.Villain.Blocks.TextBlock{
                uid: "1wUr4ZLoOx53fqIslbP1dg",
                type: "text",
                active: true,
                data: %Brando.Villain.Blocks.TextBlock.Data{
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
              type: :text,
              value: "VARIABLE!"
            }
          ]
        }
      }
    ]

    page_params = Factory.params_for(:page, %{creator_id: user.id})
    page_cs = Brando.Pages.Page.changeset(%Brando.Pages.Page{}, page_params, user)
    page_cs = Ecto.Changeset.put_assoc(page_cs, :entry_blocks, simple_blocks)
    page_cs = Map.put(page_cs, :action, :insert)
    {:ok, page} = Brando.Pages.create_page(page_cs, user)
    {:ok, page} = Brando.Villain.render_entry(Brando.Pages.Page, page.id)

    assert page.rendered_blocks ==
             "A variable: VARIABLE! -- A ref: <div class=\"lede\"><p>A REF!</p></div>"
  end

  test "headless refs are ignored", %{user: user} do
    module_params =
      Factory.params_for(:module, %{
        code: "A variable: {{ testvar }} -- A ref:{% headless_ref refs.lede %}",
        name: "Name",
        help_text: "Help text",
        refs: [],
        namespace: "all",
        class: "css class"
      })

    {:ok, module} = Brando.Content.create_module(module_params, user)
    params = Factory.params_for(:page, creator_id: user.id)

    cs =
      %Brando.Pages.Page{}
      |> Ecto.Changeset.change(params)
      |> Ecto.Changeset.put_assoc(:entry_blocks, [
        %{
          block: %{
            module_id: module.id,
            source: "Elixir.Brando.Pages.Page.Blocks",
            uid: "1wUr4ZLoOx53fqIslbP1dg",
            multi: false,
            refs: [
              %{
                data: %Brando.Villain.Blocks.TextBlock{
                  uid: "1wUr4ZLoOx53fqIslbP1dg",
                  type: :text,
                  active: true,
                  data: %Brando.Villain.Blocks.TextBlock.Data{
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
                type: :text,
                value: "VARIABLE!"
              }
            ],
            type: :module
          }
        }
      ])

    {:ok, page} = Brando.Pages.create_page(cs, user)
    {:ok, page} = Brando.Villain.render_entry(Brando.Pages.Page, page.id)

    assert page.rendered_blocks == "A variable: VARIABLE! -- A ref:"
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

    result = Brando.Villain.render_all_entries(Brando.Pages.Page)

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

    pf_params = pf_cs("**Some** {{ navigation.main.en.title }} here.")
    {:ok, pf1} = Brando.Pages.create_fragment(pf_params, user)
    {:ok, pf1} = Brando.Villain.render_entry(Brando.Pages.Fragment, pf1.id)

    Brando.Cache.Navigation.set()
    {:ok, _menu} = Brando.Navigation.update_menu(menu.id, %{title: "New title"}, user)

    pf2 = Brando.repo().get(Brando.Pages.Fragment, pf1.id)
    assert pf2.rendered_blocks == "<div class=\"paragraph\">**Some** New title here.</div>"
  end

  test "ensure villains update on globals changes", %{user: user} do
    Brando.Cache.Globals.set()

    global_set_params = %{
      label: "System",
      key: "system",
      language: "en",
      vars: [
        %{type: "text", label: "Text", key: "text", value: "My text"}
      ]
    }

    global_set_params_no = %{
      label: "System",
      key: "system",
      language: "no",
      vars: [
        %{type: "text", label: "Text", key: "text", value: "Min tekst"}
      ]
    }

    fragment_cs = pf_cs("So the global says: '{{ globals.system.text }}'.")

    {:ok, gc1} = Brando.Sites.create_global_set(global_set_params, user)
    {:ok, _} = Brando.Sites.create_global_set(global_set_params_no, user)
    {:ok, pf1} = Brando.Pages.create_fragment(fragment_cs, user)

    {:ok, pf2} =
      Brando.Pages.create_fragment(Ecto.Changeset.put_change(fragment_cs, :language, :no), user)

    {:ok, pf1} = Brando.Villain.render_entry(Brando.Pages.Fragment, pf1.id)
    {:ok, pf2} = Brando.Villain.render_entry(Brando.Pages.Fragment, pf2.id)

    assert pf1.rendered_blocks == "<div class=\"paragraph\">So the global says: 'My text'.</div>"

    assert pf2.rendered_blocks ==
             "<div class=\"paragraph\">So the global says: 'Min tekst'.</div>"

    Brando.Sites.update_global_set(
      gc1.id,
      %{
        vars: [
          %{
            type: "text",
            label: "Text",
            key: "text",
            value: "My replaced text",
            creator_id: user.id
          }
        ]
      },
      :system
    )

    pf2 = Brando.repo().get(Brando.Pages.Fragment, pf1.id)

    assert pf2.rendered_blocks ==
             "<div class=\"paragraph\">So the global says: 'My replaced text'.</div>"
  end

  test "ensure villains update on identity changes", %{user: user} do
    Brando.Cache.Identity.set()

    pf_params = pf_cs("So identity.name says: '{{ identity.name }}'.")

    {:ok, pf1} = Brando.Pages.create_fragment(pf_params, user)
    {:ok, pf1} = Brando.Villain.render_entry(Brando.Pages.Fragment, pf1.id)

    assert pf1.rendered_blocks ==
             "<div class=\"paragraph\">So identity.name says: 'Organization name'.</div>"

    {:ok, identity} = Brando.Sites.get_identity(%{matches: %{language: "en"}})
    Brando.Sites.update_identity(identity, %{name: "Eddie Hazel Inc"}, user)

    pf2 = Brando.repo().get(Brando.Pages.Fragment, pf1.id)

    assert pf2.rendered_blocks ==
             "<div class=\"paragraph\">So identity.name says: 'Eddie Hazel Inc'.</div>"

    {:ok, identity} = Brando.Sites.get_identity(%{matches: %{language: "en"}})
    Brando.Sites.update_identity(identity, %{name: "Organization name"}, user)
  end

  test "ensure villains update on link changes", %{user: user} do
    Brando.Cache.Identity.set()

    pf_cs = pf_cs("So links.instagram.url says: '{{ links.instagram.url }}'.")

    {:ok, pf1} = Brando.Pages.create_fragment(pf_cs, user)
    {:ok, pf1} = Brando.Villain.render_entry(Brando.Pages.Fragment, pf1.id)

    assert pf1.rendered_blocks ==
             "<div class=\"paragraph\">So links.instagram.url says: 'https://instagram.com/test'.</div>"

    {:ok, identity} = Brando.Sites.get_identity(%{matches: %{language: "en"}})

    Brando.Sites.update_identity(
      identity,
      %{links: [%{name: "Instagram", url: "https://instagram.com"}]},
      user
    )

    pf2 = Brando.repo().get(Brando.Pages.Fragment, pf1.id)

    assert pf2.rendered_blocks ==
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

  test "fragment block", %{user: user} do
    f1 =
      Factory.insert(:fragment, %{
        parent_key: "parent_test_fragment_block",
        key: "frag_key_fragment_block",
        rendered_blocks: "Hello from the FRAGMENT!"
      })

    fragment_block = [
      %{
        block: %{
          type: :fragment,
          source: "Elixir.Brando.Pages.Fragment.Blocks",
          fragment_id: f1.id,
          sequence: 0
        }
      }
    ]

    page_params = Factory.params_for(:page, %{creator_id: user.id})
    page_cs = Brando.Pages.Page.changeset(%Brando.Pages.Page{}, page_params, user)
    page_cs = Ecto.Changeset.put_assoc(page_cs, :entry_blocks, fragment_block)
    page_cs = Map.put(page_cs, :action, :insert)
    {:ok, page} = Brando.Pages.create_page(page_cs, user)
    {:ok, page} = Brando.Villain.render_entry(Brando.Pages.Page, page.id)

    assert page.rendered_blocks == "Hello from the FRAGMENT!"
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

  test "render template locale by entry's language", %{user: _user} do
    # TODO
    # pf_params =
    #   pf_data("""
    #   {% if locale == "en" %}
    #     ENGLISH
    #   {% else %}
    #     NORWEGIAN
    #   {% endif %}
    #   """)
    #   |> Map.put(:language, "en")

    # {:ok, pf1} = Brando.Pages.create_fragment(pf_params, user)
    # assert pf1.html == "<div class=\"paragraph\">\n  ENGLISH\n\n</div>"

    # {:ok, pf2} = Brando.Pages.update_fragment(pf1, %{"language" => "no"}, user)
    # assert pf2.html == "<div class=\"paragraph\">\n  NORWEGIAN\n\n</div>"
  end
end
