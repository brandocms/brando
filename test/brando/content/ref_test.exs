defmodule Brando.Content.RefTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase
  alias Brando.Factory
  alias Brando.Content
  alias Brando.Repo
  import Ecto.Query

  setup do
    user = Factory.insert(:random_user)
    image = Factory.insert(:image, creator: user)
    video = Factory.insert(:video, creator: user)
    gallery = Factory.insert(:gallery)
    {:ok, %{user: user, image: image, video: video, gallery: gallery}}
  end

  describe "ref database persistence" do
    test "refs are persisted as separate database entities", %{user: user, image: image} do
      module_params =
        Factory.params_for(:module, %{
          refs: [
            %{
              uid: Brando.Utils.generate_uid(),
              name: "picture_ref",
              description: "A picture ref",
              image_id: image.id,
              data: %{
                type: "picture",
                data: %{
                  title: "Test title",
                  alt: "Test alt"
                }
              }
            }
          ]
        })

      {:ok, module} = Content.create_module(module_params, user)

      # Verify refs exist in database as separate entities
      refs = Repo.all(from r in Content.Ref, where: r.module_id == ^module.id)
      assert length(refs) == 1

      ref = List.first(refs)
      assert ref.name == "picture_ref"
      assert ref.description == "A picture ref"
      assert ref.image_id == image.id
      assert ref.data.type == "picture"
      assert ref.data.data.title == "Test title"
      assert ref.data.data.alt == "Test alt"
    end

    test "multiple refs with different associations", %{user: user, image: image, video: video, gallery: gallery} do
      module_params =
        Factory.params_for(:module, %{
          refs: [
            %{
              uid: Brando.Utils.generate_uid(),
              name: "cover_image",
              image_id: image.id,
              data: %{type: "picture", data: %{title: "Cover Image"}}
            },
            %{
              uid: Brando.Utils.generate_uid(),
              name: "hero_video",
              video_id: video.id,
              data: %{type: "video", data: %{autoplay: true}}
            },
            %{
              uid: Brando.Utils.generate_uid(),
              name: "photo_gallery",
              gallery_id: gallery.id,
              data: %{type: "gallery", data: %{}}
            },
            %{
              uid: Brando.Utils.generate_uid(),
              name: "headline",
              data: %{type: "text", data: %{text: "Main Headline", type: :paragraph}}
            }
          ]
        })

      {:ok, module} = Content.create_module(module_params, user)

      refs = Repo.all(from r in Content.Ref, where: r.module_id == ^module.id, order_by: :name)
      assert length(refs) == 4

      # Check each ref type
      cover_ref = Enum.find(refs, &(&1.name == "cover_image"))
      assert cover_ref.image_id == image.id
      assert is_nil(cover_ref.video_id)
      assert is_nil(cover_ref.gallery_id)

      video_ref = Enum.find(refs, &(&1.name == "hero_video"))
      assert video_ref.video_id == video.id
      assert is_nil(video_ref.image_id)

      gallery_ref = Enum.find(refs, &(&1.name == "photo_gallery"))
      assert gallery_ref.gallery_id == gallery.id

      text_ref = Enum.find(refs, &(&1.name == "headline"))
      assert is_nil(text_ref.image_id)
      assert is_nil(text_ref.video_id)
      assert is_nil(text_ref.gallery_id)
    end

    test "ref associations are properly loaded", %{user: user, image: image} do
      module_params =
        Factory.params_for(:module, %{
          refs: [
            %{
              uid: Brando.Utils.generate_uid(),
              name: "cover",
              image_id: image.id,
              data: %{type: "picture", data: %{}}
            }
          ]
        })

      {:ok, module} = Content.create_module(module_params, user)

      # Get module with preloaded refs
      {:ok, loaded_module} =
        Content.get_module(%{
          matches: %{id: module.id},
          preload: [refs: [:image]]
        })

      ref = List.first(loaded_module.refs)
      assert ref.image.id == image.id
      assert ref.image.path == image.path
      assert ref.image.title == image.title
    end

    test "refs can be updated and deleted", %{user: user, image: image} do
      # Create module with ref
      module_params =
        Factory.params_for(:module, %{
          refs: [
            %{
              uid: Brando.Utils.generate_uid(),
              name: "test_ref",
              image_id: image.id,
              data: %{type: "picture", data: %{title: "Original Title"}}
            }
          ]
        })

      {:ok, module} = Content.create_module(module_params, user)
      original_ref = List.first(module.refs)

      # Update the module's refs
      update_params = %{
        refs: [
          %{
            id: original_ref.id,
            name: "test_ref",
            image_id: image.id,
            data: %{type: "picture", data: %{title: "Updated Title"}}
          }
        ]
      }

      {:ok, updated_module} = Content.update_module(module, update_params, user)
      updated_ref = List.first(updated_module.refs)

      assert updated_ref.id == original_ref.id
      assert updated_ref.data.data.title == "Updated Title"

      # Verify in database
      db_ref = Repo.get(Content.Ref, original_ref.id)
      assert db_ref.data.data.title == "Updated Title"
    end
  end

  describe "protected attributes" do
    test "SVG blocks preserve protected code attribute" do
      # Create a module with SVG ref
      module_with_svg = %Content.Module{
        vars: [],
        refs: [
          %Content.Ref{
            uid: Brando.Utils.generate_uid(),
            name: "svg_icon",
            data: %Brando.Villain.Blocks.SvgBlock{
              type: "svg",
              data: %Brando.Villain.Blocks.SvgBlock.Data{
                class: "original-class",
                code: "<svg>original code</svg>"
              }
            }
          }
        ]
      }

      # Create a block with SVG ref that tries to overwrite protected code
      original_block = %Content.Block{
        vars: [],
        refs: [
          %Content.Ref{
            name: "svg_icon",
            data: %Brando.Villain.Blocks.SvgBlock{
              type: "svg",
              data: %Brando.Villain.Blocks.SvgBlock.Data{
                class: "block-class",
                code: "<svg>block code should be preserved</svg>"
              }
            }
          }
        ]
      }

      # Apply ref - should update class but preserve code
      updated_block_cs = Brando.Villain.sync_module(original_block, module_with_svg)
      updated_block = Ecto.Changeset.apply_changes(updated_block_cs)

      svg_ref = List.first(updated_block.refs)

      # Class should be updated from module
      assert svg_ref.data.data.class == "original-class"

      # Code should be preserved from block (protected attribute)
      assert svg_ref.data.data.code == "<svg>block code should be preserved</svg>"
    end

    test "text blocks have protected text attribute" do
      module_with_text = %Content.Module{
        vars: [],
        refs: [
          %Content.Ref{
            name: "headline",
            data: %Brando.Villain.Blocks.TextBlock{
              type: "text",
              data: %Brando.Villain.Blocks.TextBlock.Data{
                text: "Module Headline",
                type: :paragraph
              }
            }
          }
        ]
      }

      original_block = %Content.Block{
        vars: [],
        refs: [
          %Content.Ref{
            name: "headline",
            data: %Brando.Villain.Blocks.TextBlock{
              type: "text",
              data: %Brando.Villain.Blocks.TextBlock.Data{
                text: "Block Headline",
                type: :paragraph
              }
            }
          }
        ]
      }

      updated_block_cs = Brando.Villain.sync_module(original_block, module_with_text)
      updated_block = Ecto.Changeset.apply_changes(updated_block_cs)

      text_ref = List.first(updated_block.refs)

      # Text should be preserved (protected attribute), type updated
      assert text_ref.data.data.text == "Block Headline"
      assert text_ref.data.data.type == :paragraph
    end
  end

  describe "error handling" do
    test "handles missing image association gracefully", %{user: user} do
      module_params =
        Factory.params_for(:module, %{
          refs: [
            %{
              uid: Brando.Utils.generate_uid(),
              name: "broken_picture",
              data: %{type: "picture", data: %{}}
            }
          ]
        })

      # Should create the module successfully  
      {:ok, module} = Content.create_module(module_params, user)
      assert length(module.refs) == 1

      # Ref should exist without image association
      ref = List.first(module.refs)
      assert is_nil(ref.image_id)
      assert ref.data.type == "picture"
    end

    test "handles malformed ref data gracefully", %{user: user} do
      # Create module with minimal ref data
      module_params =
        Factory.params_for(:module, %{
          refs: [
            %{
              uid: Brando.Utils.generate_uid(),
              name: "minimal_ref",
              data: %{type: "text", data: %{}}
            }
          ]
        })

      {:ok, module} = Content.create_module(module_params, user)
      ref = List.first(module.refs)

      assert ref.name == "minimal_ref"
      assert ref.data.type == "text"
      # Check that default values are applied
      assert ref.data.data.text == nil
      assert ref.data.data.type == :paragraph
    end

    test "gracefully handles missing refs during sync" do
      # Module has a ref that doesn't exist in the block
      module_with_extra_ref = %Content.Module{
        vars: [],
        refs: [
          %Content.Ref{
            name: "existing_ref",
            data: %Brando.Villain.Blocks.TextBlock{
              type: "text",
              data: %Brando.Villain.Blocks.TextBlock.Data{text: "Module text", type: :paragraph}
            }
          },
          %Content.Ref{
            name: "new_ref",
            data: %Brando.Villain.Blocks.TextBlock{
              type: "text",
              data: %Brando.Villain.Blocks.TextBlock.Data{text: "New text", type: :paragraph}
            }
          }
        ]
      }

      # Block only has one ref
      original_block = %Content.Block{
        vars: [],
        refs: [
          %Content.Ref{
            name: "existing_ref",
            data: %Brando.Villain.Blocks.TextBlock{
              type: "text",
              data: %Brando.Villain.Blocks.TextBlock.Data{text: "Block text", type: :paragraph}
            }
          }
        ]
      }

      # Should add the missing ref and update existing one
      updated_block_cs = Brando.Villain.sync_module(original_block, module_with_extra_ref)
      updated_block = Ecto.Changeset.apply_changes(updated_block_cs)

      assert length(updated_block.refs) == 2

      existing_ref = Enum.find(updated_block.refs, &(&1.name == "existing_ref"))
      new_ref = Enum.find(updated_block.refs, &(&1.name == "new_ref"))

      assert existing_ref.data.data.text == "Block text"
      assert new_ref.data.data.text == "New text"
    end

    test "handles refs with missing module refs during reapply" do
      # This tests the error condition where a ref exists in a block
      # but the corresponding ref is removed from the module
      module_with_missing_ref = %Content.Module{
        id: 1,
        name: "Test Module",
        namespace: "test",
        vars: [],
        # Module has no refs
        refs: []
      }

      # Block has a ref that no longer exists in module
      original_block = %Content.Block{
        module_id: 1,
        vars: [],
        refs: [
          %Content.Ref{
            name: "orphaned_ref",
            data: %Brando.Villain.Blocks.TextBlock{
              type: "text",
              data: %Brando.Villain.Blocks.TextBlock.Data{text: "Orphaned text", type: :paragraph}
            }
          }
        ]
      }

      # Should remove the orphaned ref
      updated_block_cs = Brando.Villain.sync_module(original_block, module_with_missing_ref)
      updated_block = Ecto.Changeset.apply_changes(updated_block_cs)

      assert length(updated_block.refs) == 0
    end
  end

  describe "ref rendering integration" do
    test "refs render correctly in module parsing", %{user: user, image: image} do
      # Create module with refs
      module_params =
        Factory.params_for(:module, %{
          code: "Title: {% ref refs.title %} | Image: {% ref refs.cover %}",
          refs: [
            %{
              uid: Brando.Utils.generate_uid(),
              name: "title",
              data: %{type: "text", data: %{text: "Test Title", type: "paragraph"}}
            },
            %{
              uid: Brando.Utils.generate_uid(),
              name: "cover",
              image_id: image.id,
              data: %{type: "picture", data: %{alt: "Cover image"}}
            }
          ]
        })

      {:ok, module} = Content.create_module(module_params, user)

      # Create a block that uses this module
      block = %{
        block: %{
          type: :module,
          module_id: module.id,
          refs: [
            %{
              uid: Brando.Utils.generate_uid(),
              name: "title",
              description: nil,
              data: %Brando.Villain.Blocks.TextBlock{
                type: "text",
                data: %Brando.Villain.Blocks.TextBlock.Data{
                  text: "Override Title",
                  type: :paragraph
                }
              }
            },
            %{
              uid: Brando.Utils.generate_uid(),
              name: "cover",
              description: nil,
              image_id: image.id,
              image: image,
              data: %Brando.Villain.Blocks.PictureBlock{
                type: "picture",
                data: %Brando.Villain.Blocks.PictureBlock.Data{
                  alt: "Override alt"
                }
              }
            }
          ],
          uid: Brando.Utils.generate_uid(),
          vars: []
        }
      }

      # Parse the block
      parsed = Brando.Villain.parse([block], %Brando.Pages.Page{})

      # Should contain the overridden content
      assert parsed =~ "Override Title"
      assert parsed =~ "Override alt"
      assert parsed =~ "/media/image/"
    end
  end
end
