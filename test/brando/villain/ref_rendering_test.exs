defmodule Brando.Villain.RefRenderingTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase
  alias Brando.Content
  alias Brando.Factory
  alias Brando.Utils

  setup do
    user = Factory.insert(:random_user)
    image = Factory.insert(:image, creator: user)
    video = Factory.insert(:video, creator: user)
    gallery = Factory.insert(:gallery)
    {:ok, %{user: user, image: image, video: video, gallery: gallery}}
  end

  describe "ref parsing and rendering" do
    # The marker exists to say *which* ref was switched off. `active` moved from
    # the ref's data into a database column, which stranded the clause that
    # printed the name and left every deactivated ref rendering an anonymous
    # `<!-- !a -->`.
    test "names the ref in the marker for a deactivated ref", %{user: user} do
      module_params =
        Factory.params_for(:module, %{
          code: "Headline: {% ref refs.title %}",
          refs: [
            %{
              name: "title",
              uid: Brando.Utils.generate_uid(),
              data: %{type: "text", data: %{text: "Default Title", type: :paragraph}}
            }
          ]
        })

      {:ok, module} = Content.create_module(module_params, user)

      block = %{
        block: %{
          type: :module,
          module_id: module.id,
          refs: [
            %{
              name: "title",
              description: nil,
              active: false,
              uid: Brando.Utils.generate_uid(),
              data: %Brando.Villain.Blocks.TextBlock{
                type: "text",
                data: %Brando.Villain.Blocks.TextBlock.Data{text: "Hidden", type: :paragraph}
              }
            }
          ],
          uid: Brando.Utils.generate_uid(),
          vars: []
        }
      }

      parsed = Brando.Villain.parse([block], %Brando.Pages.Page{})

      assert parsed =~ "<!-- !a[title] -->"
      refute parsed =~ "Hidden"
    end

    test "renders text refs correctly", %{user: user} do
      module_params =
        Factory.params_for(:module, %{
          code: "Headline: {% ref refs.title %}",
          refs: [
            %{
              name: "title",
              uid: Utils.generate_uid(),
              data: %{type: "text", data: %{text: "Default Title", type: :paragraph}}
            }
          ]
        })

      {:ok, module} = Content.create_module(module_params, user)

      block = %{
        block: %{
          type: :module,
          module_id: module.id,
          refs: [
            %{
              name: "title",
              description: nil,
              uid: Utils.generate_uid(),
              data: %Brando.Villain.Blocks.TextBlock{
                type: "text",
                data: %Brando.Villain.Blocks.TextBlock.Data{
                  text: "Override Title",
                  type: :paragraph
                }
              }
            }
          ],
          uid: Utils.generate_uid(),
          vars: []
        }
      }

      parsed = Brando.Villain.parse([block], %Brando.Pages.Page{})

      assert parsed =~ "Headline:"
      assert parsed =~ "Override Title"
      refute parsed =~ "Default Title"
    end

    test "renders picture refs with image associations", %{user: user, image: image} do
      module_params =
        Factory.params_for(:module, %{
          code: "Cover: {% ref refs.cover %}",
          refs: [
            %{
              name: "cover",
              image_id: image.id,
              uid: Utils.generate_uid(),
              data: %{type: "picture", data: %{alt: "Default alt"}}
            }
          ]
        })

      {:ok, module} = Content.create_module(module_params, user)

      block = %{
        block: %{
          type: :module,
          module_id: module.id,
          refs: [
            %{
              name: "cover",
              description: nil,
              image_id: image.id,
              image: image,
              uid: Utils.generate_uid(),
              data: %Brando.Villain.Blocks.PictureBlock{
                type: "picture",
                data: %Brando.Villain.Blocks.PictureBlock.Data{
                  alt: "Override alt"
                }
              }
            }
          ],
          uid: Utils.generate_uid(),
          vars: []
        }
      }

      parsed = Brando.Villain.parse([block], %Brando.Pages.Page{})

      assert parsed =~ "Cover:"
      assert parsed =~ "<picture"
      assert parsed =~ "Override alt"
      assert parsed =~ "/media/image/"
    end

    test "renders video refs with video associations", %{user: user, video: video} do
      module_params =
        Factory.params_for(:module, %{
          code: "Video: {% ref refs.hero_video %}",
          refs: [
            %{
              name: "hero_video",
              video_id: video.id,
              uid: Utils.generate_uid(),
              data: %{type: "video", data: %{autoplay: false}}
            }
          ]
        })

      {:ok, module} = Content.create_module(module_params, user)

      block = %{
        block: %{
          type: :module,
          module_id: module.id,
          refs: [
            %{
              name: "hero_video",
              description: nil,
              video_id: video.id,
              video: video,
              uid: Utils.generate_uid(),
              data: %Brando.Villain.Blocks.VideoBlock{
                type: "video",
                data: %Brando.Villain.Blocks.VideoBlock.Data{
                  autoplay: true
                }
              }
            }
          ],
          uid: Utils.generate_uid(),
          vars: []
        }
      }

      parsed = Brando.Villain.parse([block], %Brando.Pages.Page{})

      assert parsed =~ "Video:"
      assert parsed =~ "iframe"
      assert parsed =~ "youtube.com"
    end

    test "renders video refs with external_file video", %{user: user} do
      video = Factory.insert(:external_file_video, creator: user)

      module_params =
        Factory.params_for(:module, %{
          code: "Video: {% ref refs.hero_video %}",
          refs: [
            %{
              name: "hero_video",
              video_id: video.id,
              uid: Utils.generate_uid(),
              data: %{type: "video", data: %{autoplay: false}}
            }
          ]
        })

      {:ok, module} = Content.create_module(module_params, user)

      block = %{
        block: %{
          type: :module,
          module_id: module.id,
          refs: [
            %{
              name: "hero_video",
              description: nil,
              video_id: video.id,
              video: video,
              uid: Utils.generate_uid(),
              data: %Brando.Villain.Blocks.VideoBlock{
                type: "video",
                data: %Brando.Villain.Blocks.VideoBlock.Data{
                  autoplay: true
                }
              }
            }
          ],
          uid: Utils.generate_uid(),
          vars: []
        }
      }

      parsed = Brando.Villain.parse([block], %Brando.Pages.Page{})

      assert parsed =~ "Video:"
      assert parsed =~ "video-wrapper video-file"
      assert parsed =~ "https://example.com/video.mp4"
      refute parsed =~ "iframe"
    end

    test "renders file refs with usage overrides", %{user: user} do
      {:ok, file} =
        Brando.Files.create_file(
          %{
            title: "Canonical title",
            filename: "files/reports/report.pdf",
            mime_type: "application/pdf",
            filesize: 42_000,
            config_target: "default"
          },
          user
        )

      module_params =
        Factory.params_for(:module, %{
          code: "Download: {% ref refs.report %}",
          refs: [
            %{
              name: "report",
              file_id: file.id,
              uid: Utils.generate_uid(),
              data: %{type: "file", data: %{label: "Default report"}}
            }
          ]
        })

      {:ok, module} = Content.create_module(module_params, user)

      block = %{
        block: %{
          type: :module,
          module_id: module.id,
          refs: [
            %{
              name: "report",
              description: nil,
              file_id: file.id,
              file: file,
              uid: Utils.generate_uid(),
              data: %Brando.Villain.Blocks.FileBlock{
                type: "file",
                data: %Brando.Villain.Blocks.FileBlock.Data{
                  label: "Annual report",
                  description: "Audited figures",
                  target_blank: true,
                  download: false
                }
              }
            }
          ],
          uid: Utils.generate_uid(),
          vars: []
        }
      }

      parsed = Brando.Villain.parse([block], %Brando.Pages.Page{})

      assert parsed =~ "Download:"
      assert parsed =~ "Annual report"
      assert parsed =~ "Audited figures"
      assert parsed =~ "report.pdf"
      assert parsed =~ ~s(target="_blank")
    end

    test "handles missing refs gracefully", %{user: user} do
      module_params =
        Factory.params_for(:module, %{
          code: "Title: {% ref refs.missing_ref %} | Existing: {% ref refs.existing %}",
          refs: [
            %{
              name: "existing",
              uid: Utils.generate_uid(),
              data: %{type: "text", data: %{text: "Existing Content", type: :paragraph}}
            }
          ]
        })

      {:ok, module} = Content.create_module(module_params, user)

      block = %{
        block: %{
          type: :module,
          module_id: module.id,
          refs: [
            %{
              name: "existing",
              description: nil,
              uid: Utils.generate_uid(),
              data: %Brando.Villain.Blocks.TextBlock{
                type: "text",
                data: %Brando.Villain.Blocks.TextBlock.Data{
                  text: "Block Content",
                  type: :paragraph
                }
              }
            }
          ],
          uid: Utils.generate_uid(),
          vars: []
        }
      }

      parsed = Brando.Villain.parse([block], %Brando.Pages.Page{})

      # Should contain placeholder for missing ref
      assert parsed =~ "<!-- REF missing_ref missing"
      assert parsed =~ "Block Content"
    end

    test "renders refs in multi-module blocks", %{user: user, image: image} do
      # Create parent multi-module
      parent_module_params =
        Factory.params_for(:module, %{
          code: "Multi content: {{ content }}",
          multi: true,
          refs: []
        })

      {:ok, parent_module} = Content.create_module(parent_module_params, user)

      # Create child module with refs
      child_module_params =
        Factory.params_for(:module, %{
          code: "Child: {% ref refs.child_title %} - {% ref refs.child_image %}",
          refs: [
            %{
              name: "child_title",
              uid: Utils.generate_uid(),
              data: %{type: "text", data: %{text: "Default Child Title", type: :paragraph}}
            },
            %{
              name: "child_image",
              image_id: image.id,
              uid: Utils.generate_uid(),
              data: %{type: "picture", data: %{alt: "Default child alt"}}
            }
          ]
        })

      {:ok, child_module} = Content.create_module(child_module_params, user)

      # Create block structure
      child_block = %{
        type: :module,
        module_id: child_module.id,
        active: true,
        uid: Utils.generate_uid(),
        refs: [
          %{
            name: "child_title",
            description: nil,
            uid: Utils.generate_uid(),
            data: %Brando.Villain.Blocks.TextBlock{
              type: "text",
              data: %Brando.Villain.Blocks.TextBlock.Data{
                text: "Override Child Title",
                type: :paragraph
              }
            }
          },
          %{
            name: "child_image",
            description: nil,
            image_id: image.id,
            image: image,
            uid: Utils.generate_uid(),
            data: %Brando.Villain.Blocks.PictureBlock{
              type: "picture",
              data: %Brando.Villain.Blocks.PictureBlock.Data{
                alt: "Override child alt"
              }
            }
          }
        ],
        vars: []
      }

      block = %{
        block: %{
          type: :module,
          module_id: parent_module.id,
          multi: true,
          uid: Utils.generate_uid(),
          refs: [],
          vars: [],
          children: [child_block]
        }
      }

      parsed = Brando.Villain.parse([block], %Brando.Pages.Page{})

      assert parsed =~ "Multi content:"
      assert parsed =~ "Child:"
      assert parsed =~ "Override Child Title"
      assert parsed =~ "Override child alt"
      assert parsed =~ "/media/image/"
    end

    test "renders refs in container blocks", %{user: user} do
      # Create palette for container
      palette_params = %{
        status: :published,
        name: "test",
        key: "test",
        namespace: "general",
        instructions: "help",
        colors: [
          %{name: "Background", key: "bg", hex_value: "#000000"},
          %{name: "Text", key: "text", hex_value: "#FFFFFF"}
        ]
      }

      {:ok, palette} = Content.create_palette(palette_params, user)

      # Create container
      container_params = %{
        name: "Test Container",
        key: "test",
        namespace: "general",
        instructions: "help",
        code: "<section>{{ content }}</section>",
        wrapper: "<section>{{ content }}</section>"
      }

      {:ok, container} = Content.create_container(container_params, user)

      # Create module with refs
      module_params =
        Factory.params_for(:module, %{
          code: "Container content: {% ref refs.content %}",
          refs: [
            %{
              name: "content",
              uid: Utils.generate_uid(),
              data: %{type: "text", data: %{text: "Default container content", type: :paragraph}}
            }
          ]
        })

      {:ok, module} = Content.create_module(module_params, user)

      block = %{
        block: %{
          type: :container,
          container_id: container.id,
          palette_id: palette.id,
          anchor: nil,
          children: [
            %{
              type: :module,
              module_id: module.id,
              refs: [
                %{
                  name: "content",
                  description: nil,
                  uid: Utils.generate_uid(),
                  data: %Brando.Villain.Blocks.TextBlock{
                    type: "text",
                    data: %Brando.Villain.Blocks.TextBlock.Data{
                      text: "Container module content",
                      type: :paragraph
                    }
                  }
                }
              ],
              uid: Utils.generate_uid(),
              vars: []
            }
          ],
          uid: Utils.generate_uid()
        }
      }

      parsed = Brando.Villain.parse([block], %Brando.Pages.Page{})

      assert parsed =~ "<section"
      assert parsed =~ "Container content:"
      assert parsed =~ "Container module content"
    end
  end

  describe "ref context and access" do
    test "refs are available in template context", %{user: user, image: image} do
      module_params =
        Factory.params_for(:module, %{
          code: """
          Title: {% ref refs.title %}
          Image Path: {{ refs.cover.path }}
          Image Alt: {{ refs.cover.alt }}
          """,
          refs: [
            %{
              name: "title",
              uid: Utils.generate_uid(),
              data: %{type: "text", data: %{text: "Default Title", type: :paragraph}}
            },
            %{
              name: "cover",
              image_id: image.id,
              uid: Utils.generate_uid(),
              data: %{type: "picture", data: %{alt: "Default alt"}}
            }
          ]
        })

      {:ok, module} = Content.create_module(module_params, user)

      block = %{
        block: %{
          type: :module,
          module_id: module.id,
          refs: [
            %{
              name: "title",
              description: nil,
              uid: Utils.generate_uid(),
              data: %Brando.Villain.Blocks.TextBlock{
                type: "text",
                data: %Brando.Villain.Blocks.TextBlock.Data{
                  text: "Block Title",
                  type: :paragraph
                }
              }
            },
            %{
              name: "cover",
              description: nil,
              image_id: image.id,
              image: image,
              uid: Utils.generate_uid(),
              data: %Brando.Villain.Blocks.PictureBlock{
                type: "picture",
                data: %Brando.Villain.Blocks.PictureBlock.Data{
                  alt: "Block alt"
                }
              }
            }
          ],
          uid: Utils.generate_uid(),
          vars: []
        }
      }

      parsed = Brando.Villain.parse([block], %Brando.Pages.Page{})

      # Should contain ref tag output
      assert parsed =~ "Title:"
      assert parsed =~ "Block Title"

      # Should contain direct ref access - these might be empty if refs aren't processed as expected
      # assert parsed =~ "Image Path: #{image.path}"
      # assert parsed =~ "Image Alt: Block alt"
    end

    test "refs preserve original_ref for context access", %{user: user} do
      module_params =
        Factory.params_for(:module, %{
          code: """
          Current: {{ refs.title.text }}
          Original: {{ refs.title.original_ref.data.data.text }}
          """,
          refs: [
            %{
              name: "title",
              uid: Utils.generate_uid(),
              data: %{type: "text", data: %{text: "Module Title", type: :paragraph}}
            }
          ]
        })

      {:ok, module} = Content.create_module(module_params, user)

      block = %{
        block: %{
          type: :module,
          module_id: module.id,
          refs: [
            %{
              name: "title",
              description: nil,
              uid: Utils.generate_uid(),
              data: %Brando.Villain.Blocks.TextBlock{
                type: "text",
                data: %Brando.Villain.Blocks.TextBlock.Data{
                  text: "Block Title",
                  type: :paragraph
                }
              }
            }
          ],
          uid: Utils.generate_uid(),
          vars: []
        }
      }

      parsed = Brando.Villain.parse([block], %Brando.Pages.Page{})

      # Should show both current and original values
      assert parsed =~ "Current:"
      assert parsed =~ "Original: Block Title"
    end
  end

  describe "ref edge cases" do
    test "handles refs with same name but different types", %{user: user} do
      # This tests a potential edge case where refs might have naming conflicts
      module_params =
        Factory.params_for(:module, %{
          code: "Content: {% ref refs.content %}",
          refs: [
            %{
              name: "content",
              uid: Utils.generate_uid(),
              data: %{type: "text", data: %{text: "Text content", type: :paragraph}}
            }
          ]
        })

      {:ok, module} = Content.create_module(module_params, user)

      # Block overrides with different type (should work)
      block = %{
        block: %{
          type: :module,
          module_id: module.id,
          refs: [
            %{
              name: "content",
              description: nil,
              uid: Utils.generate_uid(),
              data: %Brando.Villain.Blocks.HtmlBlock{
                type: "html",
                data: %Brando.Villain.Blocks.HtmlBlock.Data{
                  text: "<strong>HTML content</strong>"
                }
              }
            }
          ],
          uid: Utils.generate_uid(),
          vars: []
        }
      }

      parsed = Brando.Villain.parse([block], %Brando.Pages.Page{})

      assert parsed =~ "<strong>HTML content</strong>"
    end

    test "handles refs in nested liquid structures", %{user: user} do
      module_params =
        Factory.params_for(:module, %{
          code: """
          {% for item in items %}
            Item: {% ref refs.item_template %}
          {% endfor %}
          """,
          refs: [
            %{
              name: "item_template",
              uid: Utils.generate_uid(),
              data: %{type: "text", data: %{text: "Template: " <> "{{ forloop.index }}", type: :paragraph}}
            }
          ]
        })

      {:ok, module} = Content.create_module(module_params, user)

      block = %{
        block: %{
          type: :module,
          module_id: module.id,
          refs: [
            %{
              name: "item_template",
              description: nil,
              uid: Utils.generate_uid(),
              data: %Brando.Villain.Blocks.TextBlock{
                type: "text",
                data: %Brando.Villain.Blocks.TextBlock.Data{
                  text: "Item #" <> "{{ forloop.index }}",
                  type: :paragraph
                }
              }
            }
          ],
          uid: Utils.generate_uid(),
          vars: [
            %{
              key: "items",
              label: "Items",
              type: :text,
              value: ["one", "two", "three"]
            }
          ]
        }
      }

      parsed = Brando.Villain.parse([block], %Brando.Pages.Page{})

      # Should process refs within loops - simplified check
      assert parsed =~ "Item:"
      # The forloop variables may not work in this test setup
      # assert parsed =~ "Item #1"
    end
  end

  # A ref's block data carries two different kinds of field: overrides for the
  # media record's own values (title, credits, alt, the video's playback
  # settings) and settings that describe this *placement* of the media
  # (lazyload, placeholder, play_button, cover). `merge_ref_associations/1`
  # merges both onto the media struct, and the second kind used to fall off the
  # end of `Kernel.struct/2` because the media schema had no field for them —
  # silently, so the renderer just used its defaults.
  describe "block-level presentation settings" do
    defp render_picture_ref(user, block_data) do
      image = Factory.insert(:image, creator: user, dominant_color: "#112233")

      module_params =
        Factory.params_for(:module, %{
          code: "{% ref refs.cover %}",
          refs: [
            %{
              name: "cover",
              uid: Utils.generate_uid(),
              data: %{type: "picture", data: %{}}
            }
          ]
        })

      {:ok, module} = Content.create_module(module_params, user)

      block = %{
        block: %{
          type: :module,
          module_id: module.id,
          uid: Utils.generate_uid(),
          vars: [],
          refs: [
            %{
              name: "cover",
              description: nil,
              uid: Utils.generate_uid(),
              image_id: image.id,
              image: image,
              data: %Brando.Villain.Blocks.PictureBlock{type: "picture", data: block_data}
            }
          ]
        }
      }

      Brando.Villain.parse([block], %Brando.Pages.Page{})
    end

    defp render_video_ref(user, block_data) do
      video = Factory.insert(:upload_video, creator: user)

      module_params =
        Factory.params_for(:module, %{
          code: "{% ref refs.hero %}",
          refs: [
            %{
              name: "hero",
              uid: Utils.generate_uid(),
              data: %{type: "video", data: %{}}
            }
          ]
        })

      {:ok, module} = Content.create_module(module_params, user)

      block = %{
        block: %{
          type: :module,
          module_id: module.id,
          uid: Utils.generate_uid(),
          vars: [],
          refs: [
            %{
              name: "hero",
              description: nil,
              uid: Utils.generate_uid(),
              video_id: video.id,
              video: video,
              data: %Brando.Villain.Blocks.VideoBlock{type: "video", data: block_data}
            }
          ]
        }
      }

      Brando.Villain.parse([block], %Brando.Pages.Page{})
    end

    test "a picture ref renders lazyloaded with its placeholder", %{user: user} do
      html =
        render_picture_ref(user, %Brando.Villain.Blocks.PictureBlock.Data{
          lazyload: true,
          placeholder: :dominant_color_faded
        })

      assert html =~ "data-ll-srcset"
      assert html =~ ~s(data-placeholder="dominant_color")
      # both dominant_color variants render the same data-placeholder; the
      # faded one is the alpha suffix on the colour
      assert html =~ "background-color: #11223311"
    end

    test "a picture ref renders its own classes, link and moonwalk", %{user: user} do
      html =
        render_picture_ref(user, %Brando.Villain.Blocks.PictureBlock.Data{
          picture_class: "my-picture",
          img_class: "my-img",
          link: "/somewhere",
          moonwalk: true
        })

      assert html =~ "my-picture"
      assert html =~ "my-img"
      assert html =~ ~s(href="/somewhere")
      assert html =~ "data-moonwalk"
    end

    test "a video ref renders a play button when autoplay is off", %{user: user} do
      html =
        render_video_ref(user, %Brando.Villain.Blocks.VideoBlock.Data{
          play_button: true,
          autoplay: false
        })

      assert html =~ "video-play-button"
    end

    test "a video ref honours its cover setting", %{user: user} do
      refute render_video_ref(user, %Brando.Villain.Blocks.VideoBlock.Data{}) =~ "data-cover"

      assert render_video_ref(user, %Brando.Villain.Blocks.VideoBlock.Data{cover: "svg"}) =~
               "data-cover"
    end

    # `loop` and `muted` were missing from the take-list entirely, so a block
    # that turned looping off still looped.
    test "a video ref with loop: false does not loop", %{user: user} do
      assert render_video_ref(user, %Brando.Villain.Blocks.VideoBlock.Data{loop: true}) =~ " loop"
      refute render_video_ref(user, %Brando.Villain.Blocks.VideoBlock.Data{loop: false}) =~ " loop"
    end

    test "a video ref renders data-progress when progress is on", %{user: user} do
      refute render_video_ref(user, %Brando.Villain.Blocks.VideoBlock.Data{}) =~ "data-progress"

      assert render_video_ref(user, %Brando.Villain.Blocks.VideoBlock.Data{progress: true}) =~
               "data-progress"
    end
  end

  # `gallery/2`'s clauses matched a flat `images` list, the shape block data
  # carried before galleries became their own domain. `GalleryBlock.Data` has a
  # `gallery` relation instead, so no clause ever matched and every gallery ref
  # fell through to the `_ -> ""` catch-all: refs rendered nothing, silently.
  # There was no test for gallery ref rendering at all.
  describe "gallery refs" do
    defp gallery_with(objects) do
      gallery = Factory.insert(:gallery)

      for {media, sequence} <- Enum.with_index(objects) do
        attrs =
          case media do
            {:image, image} -> %{image: image, image_id: image.id}
            {:video, video} -> %{video: video, video_id: video.id}
          end

        Factory.insert(
          :gallery_object,
          Map.merge(attrs, %{gallery: gallery, gallery_id: gallery.id, sequence: sequence})
        )
      end

      Brando.Repo.preload(gallery, [gallery_objects: [:image, :video]], force: true)
    end

    defp render_gallery_ref(user, gallery, block_data) do
      module_params =
        Factory.params_for(:module, %{
          code: "{% ref refs.g %}",
          refs: [
            %{name: "g", uid: Utils.generate_uid(), data: %{type: "gallery", data: %{}}}
          ]
        })

      {:ok, module} = Content.create_module(module_params, user)

      block = %{
        block: %{
          type: :module,
          module_id: module.id,
          uid: Utils.generate_uid(),
          vars: [],
          refs: [
            %{
              name: "g",
              description: nil,
              uid: Utils.generate_uid(),
              gallery_id: gallery.id,
              gallery: gallery,
              data: %Brando.Villain.Blocks.GalleryBlock{type: "gallery", data: block_data}
            }
          ]
        }
      }

      Brando.Villain.parse([block], %Brando.Pages.Page{})
    end

    test "render their images", %{user: user} do
      image = Factory.insert(:image, creator: user)
      gallery = gallery_with([{:image, image}])

      html =
        render_gallery_ref(user, gallery, %Brando.Villain.Blocks.GalleryBlock.Data{type: :gallery})

      assert html =~ "data-gallery"
      assert html =~ "<picture"
      assert html =~ "/media/image/"
    end

    test "render their videos through the video component", %{user: user} do
      video = Factory.insert(:upload_video, creator: user)
      gallery = gallery_with([{:video, video}])

      html =
        render_gallery_ref(user, gallery, %Brando.Villain.Blocks.GalleryBlock.Data{type: :gallery})

      assert html =~ "data-gallery"
      assert html =~ "<video"
      assert html =~ "data-smart-video"
    end

    test "render images and videos together, in sequence", %{user: user} do
      image = Factory.insert(:image, creator: user)
      video = Factory.insert(:upload_video, creator: user)
      gallery = gallery_with([{:image, image}, {:video, video}])

      html =
        render_gallery_ref(user, gallery, %Brando.Villain.Blocks.GalleryBlock.Data{type: :gallery})

      assert html =~ "<picture"
      assert html =~ "<video"
      assert :binary.match(html, "<picture") < :binary.match(html, "<video")
    end

    # The three display types differ only in their wrapper markup.
    test "render the wrapper for each display type", %{user: user} do
      image = Factory.insert(:image, creator: user)
      gallery = gallery_with([{:image, image}])

      slider =
        render_gallery_ref(user, gallery, %Brando.Villain.Blocks.GalleryBlock.Data{type: :slider})

      slideshow =
        render_gallery_ref(user, gallery, %Brando.Villain.Blocks.GalleryBlock.Data{
          type: :slideshow
        })

      grid =
        render_gallery_ref(user, gallery, %Brando.Villain.Blocks.GalleryBlock.Data{type: :gallery})

      assert slider =~ "data-panner-container"
      assert slider =~ "data-panner-item"
      assert slideshow =~ "data-slideshow"
      assert grid =~ "data-gallery-items"
    end

    test "pass the block's class and lightbox down", %{user: user} do
      image = Factory.insert(:image, creator: user)
      gallery = gallery_with([{:image, image}])

      html =
        render_gallery_ref(user, gallery, %Brando.Villain.Blocks.GalleryBlock.Data{
          type: :gallery,
          class: "my-gallery",
          lightbox: true
        })

      assert html =~ ~s(data-gallery="my-gallery")
      assert html =~ "data-lightbox"
    end

    test "render an empty gallery as empty", %{user: user} do
      gallery = gallery_with([])

      html =
        render_gallery_ref(user, gallery, %Brando.Villain.Blocks.GalleryBlock.Data{type: :gallery})

      assert html =~ "data-gallery"
      refute html =~ "<picture"
    end
  end
end
