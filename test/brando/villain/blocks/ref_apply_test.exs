defmodule Brando.Villain.Blocks.RefApplyTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase
  alias Brando.Factory
  alias Brando.Content
  alias Ecto.Changeset

  setup do
    user = Factory.insert(:random_user)
    image = Factory.insert(:image, creator: user)
    video = Factory.insert(:video, creator: user)
    gallery = Factory.insert(:gallery)
    {:ok, %{user: user, image: image, video: video, gallery: gallery}}
  end

  describe "PictureBlock apply_ref" do
    test "applies picture ref correctly" do
      # Create source ref
      ref_src = %Content.Ref{
        name: "test_picture",
        data: %Brando.Villain.Blocks.PictureBlock{
          type: "picture",
          data: %Brando.Villain.Blocks.PictureBlock.Data{
            title: "Source Title",
            alt: "Source Alt",
            picture_class: "source-class",
            lazyload: true
          }
        }
      }

      # Create target ref changeset
      target_ref = %Content.Ref{
        name: "test_picture",
        data: %Brando.Villain.Blocks.PictureBlock{
          type: "picture", 
          data: %Brando.Villain.Blocks.PictureBlock.Data{
            title: "Target Title",
            alt: "Target Alt",
            picture_class: "target-class",
            lazyload: false
          }
        }
      }
      
      target_changeset = Changeset.change(target_ref)

      # Apply the ref
      result = Brando.Villain.Blocks.PictureBlock.apply_ref(
        Brando.Villain.Blocks.PictureBlock,
        ref_src,
        target_changeset
      )

      updated_ref = Changeset.apply_changes(result)

      # All attributes should be updated from source
      assert updated_ref.data.data.title == "Source Title"
      assert updated_ref.data.data.alt == "Source Alt"
      assert updated_ref.data.data.picture_class == "source-class"
      assert updated_ref.data.data.lazyload == true
    end

    test "handles MediaBlock template merging for pictures" do
      # Create MediaBlock source with template
      media_ref_src = %Content.Ref{
        name: "media_picture",
        data: %Brando.Villain.Blocks.MediaBlock{
          type: "media",
          data: %Brando.Villain.Blocks.MediaBlock.Data{
            template_picture: %Brando.Villain.Blocks.PictureBlock.Data{
              picture_class: "media-template-class",
              lazyload: true,
              placeholder: :svg
            }
          }
        }
      }

      # Create target picture ref
      target_ref = %Content.Ref{
        name: "media_picture",
        data: %Brando.Villain.Blocks.PictureBlock{
          type: "picture",
          data: %Brando.Villain.Blocks.PictureBlock.Data{
            picture_class: "original-class",
            lazyload: false,
            placeholder: :dominant_color
          }
        }
      }

      target_changeset = Changeset.change(target_ref)

      # Apply MediaBlock template
      result = Brando.Villain.Blocks.PictureBlock.apply_ref(
        Brando.Villain.Blocks.MediaBlock,
        media_ref_src,
        target_changeset
      )

      updated_ref = Changeset.apply_changes(result)

      # Should merge template data
      assert updated_ref.data.data.picture_class == "media-template-class"
      assert updated_ref.data.data.lazyload == true
      assert updated_ref.data.data.placeholder == :svg
    end
  end

  describe "VideoBlock apply_ref" do
    test "applies video ref correctly" do
      ref_src = %Content.Ref{
        name: "test_video",
        data: %Brando.Villain.Blocks.VideoBlock{
          type: "video",
          data: %Brando.Villain.Blocks.VideoBlock.Data{
            autoplay: true,
            controls: false,
            preload: true
          }
        }
      }

      target_ref = %Content.Ref{
        name: "test_video",
        data: %Brando.Villain.Blocks.VideoBlock{
          type: "video",
          data: %Brando.Villain.Blocks.VideoBlock.Data{
            autoplay: false,
            controls: true,
            preload: false
          }
        }
      }

      target_changeset = Changeset.change(target_ref)

      result = Brando.Villain.Blocks.VideoBlock.apply_ref(
        Brando.Villain.Blocks.VideoBlock,
        ref_src,
        target_changeset
      )

      updated_ref = Changeset.apply_changes(result)

      assert updated_ref.data.data.autoplay == true
      assert updated_ref.data.data.controls == false  
      assert updated_ref.data.data.preload == true
    end

    test "handles MediaBlock template merging for videos" do
      media_ref_src = %Content.Ref{
        name: "media_video",
        data: %Brando.Villain.Blocks.MediaBlock{
          type: "media",
          data: %Brando.Villain.Blocks.MediaBlock.Data{
            template_video: %Brando.Villain.Blocks.VideoBlock.Data{
              autoplay: true,
              controls: false,
              opacity: 50
            }
          }
        }
      }

      target_ref = %Content.Ref{
        name: "media_video",
        data: %Brando.Villain.Blocks.VideoBlock{
          type: "video",
          data: %Brando.Villain.Blocks.VideoBlock.Data{
            autoplay: false,
            controls: true,
            opacity: 0
          }
        }
      }

      target_changeset = Changeset.change(target_ref)

      result = Brando.Villain.Blocks.VideoBlock.apply_ref(
        Brando.Villain.Blocks.MediaBlock,
        media_ref_src,
        target_changeset
      )

      updated_ref = Changeset.apply_changes(result)

      assert updated_ref.data.data.autoplay == true
      assert updated_ref.data.data.controls == false
      assert updated_ref.data.data.opacity == 50
    end
  end

  describe "SvgBlock apply_ref with protected attributes" do
    test "preserves protected code attribute" do
      ref_src = %Content.Ref{
        name: "test_svg",
        data: %Brando.Villain.Blocks.SvgBlock{
          type: "svg",
          data: %Brando.Villain.Blocks.SvgBlock.Data{
            class: "source-svg-class",
            code: "<svg>source code</svg>"
          }
        }
      }

      target_ref = %Content.Ref{
        name: "test_svg", 
        data: %Brando.Villain.Blocks.SvgBlock{
          type: "svg",
          data: %Brando.Villain.Blocks.SvgBlock.Data{
            class: "target-svg-class",
            code: "<svg>target code should be preserved</svg>"
          }
        }
      }

      target_changeset = Changeset.change(target_ref)

      result = Brando.Villain.Blocks.SvgBlock.apply_ref(
        Brando.Villain.Blocks.SvgBlock,
        ref_src,
        target_changeset
      )

      updated_ref = Changeset.apply_changes(result)

      # Class should be updated (not protected)
      assert updated_ref.data.data.class == "source-svg-class"
      
      # Code should be preserved (protected attribute)
      assert updated_ref.data.data.code == "<svg>target code should be preserved</svg>"
    end

    test "handles MediaBlock template merging with protected attributes" do
      media_ref_src = %Content.Ref{
        name: "media_svg",
        data: %Brando.Villain.Blocks.MediaBlock{
          type: "media",
          data: %Brando.Villain.Blocks.MediaBlock.Data{
            template_svg: %Brando.Villain.Blocks.SvgBlock.Data{
              class: "media-svg-class",
              code: "<svg>template code should be ignored</svg>"
            }
          }
        }
      }

      target_ref = %Content.Ref{
        name: "media_svg",
        data: %Brando.Villain.Blocks.SvgBlock{
          type: "svg",
          data: %Brando.Villain.Blocks.SvgBlock.Data{
            class: "original-svg-class",
            code: "<svg>original code should be preserved</svg>"
          }
        }
      }

      target_changeset = Changeset.change(target_ref)

      result = Brando.Villain.Blocks.SvgBlock.apply_ref(
        Brando.Villain.Blocks.MediaBlock,
        media_ref_src,
        target_changeset
      )

      updated_ref = Changeset.apply_changes(result)

      # Class should be updated from template
      assert updated_ref.data.data.class == "media-svg-class"
      
      # Code should still be preserved (protected)
      assert updated_ref.data.data.code == "<svg>original code should be preserved</svg>"
    end
  end

  describe "TextBlock apply_ref" do
    test "applies text ref without protection" do
      ref_src = %Content.Ref{
        name: "test_text",
        data: %Brando.Villain.Blocks.TextBlock{
          type: "text",
          data: %Brando.Villain.Blocks.TextBlock.Data{
            text: "Source Text",
type: :paragraph
          }
        }
      }

      target_ref = %Content.Ref{
        name: "test_text",
        data: %Brando.Villain.Blocks.TextBlock{
          type: "text", 
          data: %Brando.Villain.Blocks.TextBlock.Data{
            text: "Target Text",
type: :paragraph
          }
        }
      }

      target_changeset = Changeset.change(target_ref)

      # TextBlock uses the default implementation
      result = Brando.Villain.Blocks.TextBlock.apply_ref(
        Brando.Villain.Blocks.TextBlock,
        ref_src,
        target_changeset
      )

      updated_ref = Changeset.apply_changes(result)

      # Text should be preserved (protected attribute), type should be updated
      assert updated_ref.data.data.text == "Target Text"
      assert updated_ref.data.data.type == :paragraph
    end
  end

  describe "HeaderBlock apply_ref" do
    test "applies header ref correctly" do
      ref_src = %Content.Ref{
        name: "test_header",
        data: %Brando.Villain.Blocks.HeaderBlock{
          type: "header",
          data: %Brando.Villain.Blocks.HeaderBlock.Data{
            text: "Source Header",
            level: 3,
            class: "source-class",
            id: "source-id"
          }
        }
      }

      target_ref = %Content.Ref{
        name: "test_header",
        data: %Brando.Villain.Blocks.HeaderBlock{
          type: "header",
          data: %Brando.Villain.Blocks.HeaderBlock.Data{
            text: "Target Header",
            level: 2,
            class: "target-class", 
            id: "target-id"
          }
        }
      }

      target_changeset = Changeset.change(target_ref)

      result = Brando.Villain.Blocks.HeaderBlock.apply_ref(
        Brando.Villain.Blocks.HeaderBlock,
        ref_src,
        target_changeset
      )

      updated_ref = Changeset.apply_changes(result)

      # Text should be preserved (protected attribute), others updated
      assert updated_ref.data.data.text == "Target Header"
      assert updated_ref.data.data.level == 3
      assert updated_ref.data.data.class == "source-class"
      assert updated_ref.data.data.id == "source-id"
    end
  end

  describe "edge cases and error handling" do
    test "handles changeset vs struct data field" do
      # Test both scenarios where data field is a changeset or a struct
      
      ref_src = %Content.Ref{
        name: "test",
        data: %Brando.Villain.Blocks.TextBlock{
          type: "text",
          data: %Brando.Villain.Blocks.TextBlock.Data{
            text: "Source Text"
          }
        }
      }

      # Scenario 1: data field is a struct
      target_ref_struct = %Content.Ref{
        name: "test",
        data: %Brando.Villain.Blocks.TextBlock{
          type: "text",
          data: %Brando.Villain.Blocks.TextBlock.Data{
            text: "Target Text"
          }
        }
      }

      target_changeset_1 = Changeset.change(target_ref_struct)

      result_1 = Brando.Villain.Blocks.TextBlock.apply_ref(
        Brando.Villain.Blocks.TextBlock,
        ref_src,
        target_changeset_1
      )

      updated_ref_1 = Changeset.apply_changes(result_1)
      assert updated_ref_1.data.data.text == "Target Text"

      # Scenario 2: data field is already a changeset  
      data_changeset = Changeset.change(target_ref_struct.data)
      target_changeset_2 = Changeset.put_change(target_changeset_1, :data, data_changeset)

      result_2 = Brando.Villain.Blocks.TextBlock.apply_ref(
        Brando.Villain.Blocks.TextBlock,
        ref_src,
        target_changeset_2
      )

      updated_ref_2 = Changeset.apply_changes(result_2)
      assert updated_ref_2.data.data.text == "Target Text"
    end

    test "handles empty or nil data gracefully" do
      ref_src = %Content.Ref{
        name: "test",
        data: %Brando.Villain.Blocks.TextBlock{
          type: "text",
          data: %Brando.Villain.Blocks.TextBlock.Data{
            text: "Source Text"
          }
        }
      }

      # Target with minimal data
      target_ref = %Content.Ref{
        name: "test",
        data: %Brando.Villain.Blocks.TextBlock{
          type: "text",
          data: %Brando.Villain.Blocks.TextBlock.Data{}
        }
      }

      target_changeset = Changeset.change(target_ref)

      result = Brando.Villain.Blocks.TextBlock.apply_ref(
        Brando.Villain.Blocks.TextBlock,
        ref_src,
        target_changeset
      )

      updated_ref = Changeset.apply_changes(result)
      # Text is protected, so it remains nil since target had empty data
      assert updated_ref.data.data.text == nil
    end
  end
end