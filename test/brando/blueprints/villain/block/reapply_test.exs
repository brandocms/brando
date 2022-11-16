defmodule Brando.Villain.Block.PictureBlockTest do
  use ExUnit.Case
  alias Brando.Villain.Blocks
  alias Brando.Content.Module
  alias Brando.Content.Module.Ref
  alias Brando.Content.Var

  test "reapply header ref" do
    updated_module = %Module{
      class: "test",
      id: 1,
      inserted_at: ~N[2022-02-07 15:23:25],
      name: "Testmodule",
      namespace: "test",
      refs: [
        %Ref{
          data: %Blocks.HeaderBlock{
            collapsed: false,
            data: %Blocks.HeaderBlock.Data{
              class: "testclass",
              id: "testid",
              level: 3,
              marked_as_deleted: false,
              placeholder: nil,
              text: "Text"
            },
            hidden: false,
            marked_as_deleted: false,
            type: "header",
            uid: "1xVOR77rLseKd3RMm0m1Pl"
          },
          description: nil,
          marked_as_deleted: false,
          name: "h2"
        }
      ],
      vars: []
    }

    original_block = %Brando.Villain.Blocks.ModuleBlock{
      collapsed: false,
      data: %Brando.Villain.Blocks.ModuleBlock.Data{
        entries: [],
        module_id: 1,
        multi: false,
        refs: [
          %Ref{
            data: %Blocks.HeaderBlock{
              collapsed: false,
              data: %Blocks.HeaderBlock.Data{
                class: nil,
                id: nil,
                level: 2,
                placeholder: nil,
                text: "Photography"
              },
              hidden: false,
              type: "header",
              uid: "1xVOTDOvPTUEMeOC6xlunJ"
            },
            description: nil,
            name: "h2"
          }
        ],
        sequence: nil,
        vars: []
      },
      hidden: false,
      marked_as_deleted: false,
      type: "module",
      uid: "1xVOTDOushEIQlh7sIihqo"
    }

    reapplied_block_data = Brando.Villain.reapply_module_data(updated_module, original_block.data)

    [orig_header_ref] = original_block.data.refs

    assert orig_header_ref.data.data.level == 2
    assert orig_header_ref.data.data.class == nil
    assert orig_header_ref.data.data.id == nil

    [applied_header_ref] = reapplied_block_data.refs

    assert applied_header_ref.data.data.level == 3
    assert applied_header_ref.data.data.class == "testclass"
    assert applied_header_ref.data.data.id == "testid"

    assert applied_header_ref.data.data.text == orig_header_ref.data.data.text
  end

  test "reapply multiple refs and vars" do
    updated_module = %Module{
      class: "entrance subidentity_dupl",
      code:
        "<article b-tpl=\"entrance insight\"{% if wide %} class=\"wide\"{% endif %} style=\"--bg: {{ bg_color }}; --fg: {{ fg_color }}\" data-moonwalk-section data-moonwalk-stage=\"scaleup\">\n  <div class=\"inner\">\n    <a href=\"{{ link_url }}\">\n      <div class=\"bg\" data-moonwalk>\n        {% ref refs.pic %}\n      </div>\n      <div class=\"heading\" data-moonwalk=\"u\">\n        {% ref refs.h2 %}\n      </div>\n    </a>\n  </div>\n</article>",
      deleted_at: nil,
      entry_template: nil,
      help_text: "Colored box with logo + symbol",
      id: 22,
      inserted_at: ~N[2022-02-07 15:23:25],
      name: "Insight",
      namespace: "entrances",
      refs: [
        %Ref{
          data: %Blocks.HeaderBlock{
            collapsed: false,
            data: %Blocks.HeaderBlock.Data{
              class: "testclass",
              id: "testid",
              level: 3,
              marked_as_deleted: false,
              placeholder: nil,
              text: "Text"
            },
            hidden: false,
            marked_as_deleted: false,
            type: "header",
            uid: "1xVOR77rLseKd3RMm0m1Pl"
          },
          description: nil,
          marked_as_deleted: false,
          name: "h2"
        },
        %Ref{
          data: %Brando.Villain.Blocks.PictureBlock{
            collapsed: false,
            data: %Brando.Villain.Blocks.PictureBlock.Data{
              alt: nil,
              cdn: false,
              credits: nil,
              dominant_color: nil,
              focal: nil,
              formats: [:original, :webp, :avif],
              height: nil,
              img_class: "img-class",
              lazyload: true,
              link: nil,
              marked_as_deleted: false,
              media_queries: nil,
              moonwalk: true,
              path: nil,
              picture_class: nil,
              placeholder: :dominant_color,
              sizes: nil,
              srcset: nil,
              title: nil,
              width: nil
            },
            hidden: false,
            marked_as_deleted: false,
            type: "picture",
            uid: "1xVOQeu7m5g2KqKRCsVaGn"
          },
          description: nil,
          marked_as_deleted: false,
          name: "pic"
        }
      ],
      sequence: 2,
      svg: nil,
      updated_at: ~N[2022-02-14 12:35:37],
      vars: [
        %Var.Boolean{
          important: true,
          instructions: nil,
          key: "wide",
          label: "Is it wide?",
          marked_as_deleted: false,
          placeholder: nil,
          type: "boolean",
          value: false
        },
        %Var.Color{
          important: true,
          instructions: nil,
          key: "bg_color",
          label: "Background color",
          marked_as_deleted: false,
          opacity: true,
          palette_id: nil,
          picker: false,
          placeholder: nil,
          type: "color",
          value: "#000000"
        }
      ],
      wrapper: false
    }

    original_block = %Brando.Villain.Blocks.ModuleBlock{
      collapsed: false,
      data: %Brando.Villain.Blocks.ModuleBlock.Data{
        entries: [],
        module_id: 22,
        multi: false,
        refs: [
          %Ref{
            data: %Blocks.HeaderBlock{
              collapsed: false,
              data: %Blocks.HeaderBlock.Data{
                class: nil,
                id: nil,
                level: 2,
                placeholder: nil,
                text: "Photography"
              },
              hidden: false,
              type: "header",
              uid: "1xVOTDOvPTUEMeOC6xlunJ"
            },
            description: nil,
            name: "h2"
          },
          %Ref{
            data: %Brando.Villain.Blocks.PictureBlock{
              collapsed: false,
              data: %Brando.Villain.Blocks.PictureBlock.Data{
                alt: nil,
                cdn: false,
                credits: nil,
                dominant_color: "#685848",
                focal: %Brando.Images.Focal{x: 50, y: 50},
                formats: [:jpg, :webp],
                height: 1575,
                img_class: nil,
                lazyload: true,
                link: nil,
                media_queries: nil,
                moonwalk: false,
                path: "images/site/default/8qti51006g6.jpg",
                picture_class: nil,
                placeholder: :svg,
                sizes: %{
                  "large" => "images/site/default/large/8qti51006g6.jpg",
                  "medium" => "images/site/default/medium/8qti51006g6.jpg",
                  "micro" => "images/site/default/micro/8qti51006g6.jpg",
                  "small" => "images/site/default/small/8qti51006g6.jpg",
                  "thumb" => "images/site/default/thumb/8qti51006g6.jpg",
                  "xlarge" => "images/site/default/xlarge/8qti51006g6.jpg"
                },
                srcset: nil,
                title: nil,
                width: 2800
              },
              hidden: false,
              type: "picture",
              uid: "1xVOTDOvSKu2TQIN3ddD3S"
            },
            description: nil,
            name: "pic"
          }
        ],
        sequence: nil,
        vars: [
          %Var.Boolean{
            important: true,
            instructions: nil,
            key: "wide",
            label: "Wide?",
            placeholder: nil,
            type: "boolean",
            value: true
          },
          %Var.Color{
            important: true,
            instructions: nil,
            key: "bg_color",
            label: "Background color",
            opacity: false,
            palette_id: nil,
            picker: true,
            placeholder: nil,
            type: "color",
            value: "#FF00FF"
          }
        ]
      },
      hidden: false,
      marked_as_deleted: false,
      type: "module",
      uid: "1xVOTDOushEIQlh7sIihqo"
    }

    reapplied_block_data = Brando.Villain.reapply_module_data(updated_module, original_block.data)

    [orig_header_ref, orig_picture_ref] = original_block.data.refs

    assert orig_header_ref.data.data.level == 2
    assert orig_header_ref.data.data.class == nil
    assert orig_header_ref.data.data.id == nil

    assert orig_picture_ref.data.data.placeholder == :svg
    assert orig_picture_ref.data.data.img_class == nil
    assert orig_picture_ref.data.data.moonwalk == false
    assert orig_picture_ref.data.data.formats == [:jpg, :webp]

    [orig_bool, orig_col] = original_block.data.vars

    assert orig_bool.key == "wide"
    assert orig_bool.label == "Wide?"
    assert orig_bool.value == true

    assert orig_col.value == "#FF00FF"
    assert orig_col.opacity == false
    assert orig_col.picker == true

    [applied_header_ref, applied_picture_ref] = reapplied_block_data.refs

    assert applied_header_ref.data.data.level == 3
    assert applied_header_ref.data.data.class == "testclass"
    assert applied_header_ref.data.data.id == "testid"

    assert applied_header_ref.data.data.text == orig_header_ref.data.data.text

    assert applied_picture_ref.data.data.placeholder == :dominant_color
    assert applied_picture_ref.data.data.img_class == "img-class"
    assert applied_picture_ref.data.data.moonwalk == true
    assert applied_picture_ref.data.data.formats == [:jpg, :webp]

    assert applied_picture_ref.data.data.sizes == orig_picture_ref.data.data.sizes
    assert applied_picture_ref.data.data.height == orig_picture_ref.data.data.height
    assert applied_picture_ref.data.data.width == orig_picture_ref.data.data.width

    assert applied_picture_ref.data.data.dominant_color ==
             orig_picture_ref.data.data.dominant_color

    assert applied_picture_ref.data.data.path == orig_picture_ref.data.data.path
    assert applied_picture_ref.data.data.focal == orig_picture_ref.data.data.focal

    [app_bool, app_col] = reapplied_block_data.vars

    assert app_bool.key == "wide"
    assert app_bool.label == "Is it wide?"
    assert app_bool.value == true

    assert app_col.value == "#FF00FF"
    assert app_col.opacity == true
    assert app_col.picker == false
  end

  test "media block" do
    updated_module = %Brando.Content.Module{
      class: "2 assets gutter",
      code:
        "<article b-tpl=\"2 assets\" class=\"gutter\">\n  <div class=\"inner\" data-moonwalk-section>\n    <div class=\"asset\" data-moonwalk=\"u\">\n      {% ref refs.asset1 %}\n    </div>\n    <div class=\"asset\" data-moonwalk=\"u\">\n      {% ref refs.asset2 %}\n    </div>\n  </div>\n</article>",
      deleted_at: nil,
      entry_template: nil,
      help_text: "Side by side (w/gutter)",
      id: 18,
      inserted_at: ~N[2022-02-10 09:13:27],
      name: "2 assets",
      namespace: "identity",
      refs: [
        %Brando.Content.Module.Ref{
          data: %Brando.Villain.Blocks.MediaBlock{
            collapsed: false,
            data: %Brando.Villain.Blocks.MediaBlock.Data{
              available_blocks: ["picture", "video", "svg"],
              marked_as_deleted: false,
              template_gallery: nil,
              template_picture: %Brando.Villain.Blocks.PictureBlock.Data{
                alt: nil,
                cdn: false,
                credits: nil,
                dominant_color: nil,
                focal: nil,
                formats: [:original, :webp],
                height: nil,
                img_class: nil,
                lazyload: false,
                link: nil,
                marked_as_deleted: false,
                media_queries: nil,
                moonwalk: false,
                path: nil,
                picture_class: nil,
                placeholder: :dominant_color,
                sizes: nil,
                srcset: nil,
                title: nil,
                width: nil
              },
              template_svg: %Brando.Villain.Blocks.SvgBlock.Data{
                class: nil,
                code: nil,
                marked_as_deleted: false
              },
              template_video: %Brando.Villain.Blocks.VideoBlock.Data{
                autoplay: true,
                cover: "false",
                height: nil,
                marked_as_deleted: false,
                opacity: 0,
                play_button: false,
                poster: nil,
                preload: true,
                remote_id: nil,
                source: nil,
                thumbnail_url: nil,
                title: nil,
                url: nil,
                width: nil
              }
            },
            hidden: false,
            marked_as_deleted: false,
            type: "media",
            uid: "1xTkuCvHo0eJGOmZ2Tjvd3"
          },
          description: nil,
          marked_as_deleted: false,
          name: "asset2"
        },
        %Brando.Content.Module.Ref{
          data: %Brando.Villain.Blocks.MediaBlock{
            collapsed: false,
            data: %Brando.Villain.Blocks.MediaBlock.Data{
              available_blocks: ["picture", "video", "svg"],
              marked_as_deleted: false,
              template_gallery: nil,
              template_picture: %Brando.Villain.Blocks.PictureBlock.Data{
                alt: nil,
                cdn: false,
                credits: nil,
                dominant_color: nil,
                focal: nil,
                formats: [:original, :webp],
                height: nil,
                img_class: nil,
                lazyload: false,
                link: nil,
                marked_as_deleted: false,
                media_queries: nil,
                moonwalk: false,
                path: nil,
                picture_class: nil,
                placeholder: :svg,
                sizes: nil,
                srcset: nil,
                title: nil,
                width: nil
              },
              template_svg: %Brando.Villain.Blocks.SvgBlock.Data{
                class: nil,
                code: nil,
                marked_as_deleted: false
              },
              template_video: %Brando.Villain.Blocks.VideoBlock.Data{
                autoplay: true,
                cover: "false",
                height: nil,
                marked_as_deleted: false,
                opacity: 0,
                play_button: false,
                poster: nil,
                preload: true,
                remote_id: nil,
                source: nil,
                thumbnail_url: nil,
                title: nil,
                url: nil,
                width: nil
              }
            },
            hidden: false,
            marked_as_deleted: false,
            type: "media",
            uid: "1xTktiszs3EAefrkah8P70"
          },
          description: nil,
          marked_as_deleted: false,
          name: "asset1"
        }
      ],
      sequence: 14,
      svg: nil,
      updated_at: ~N[2022-02-10 15:31:01],
      vars: nil,
      wrapper: false
    }

    original_block_data = %Brando.Villain.Blocks.ModuleBlock.Data{
      entries: [],
      marked_as_deleted: false,
      module_id: 18,
      multi: false,
      refs: [
        %Brando.Content.Module.Ref{
          data: %Brando.Villain.Blocks.PictureBlock{
            collapsed: false,
            data: %Brando.Villain.Blocks.PictureBlock.Data{
              alt: nil,
              cdn: false,
              credits: nil,
              dominant_color: "#582828",
              focal: %Brando.Images.Focal{x: 50, y: 50},
              formats: [:jpg, :webp],
              height: 2020,
              img_class: nil,
              lazyload: false,
              link: nil,
              marked_as_deleted: false,
              media_queries: nil,
              moonwalk: false,
              path: "images/site/default/oe2gq279qr2.jpg",
              picture_class: nil,
              placeholder: :svg,
              sizes: %{
                "large" => "images/site/default/large/oe2gq279qr2.jpg",
                "medium" => "images/site/default/medium/oe2gq279qr2.jpg",
                "micro" => "images/site/default/micro/oe2gq279qr2.jpg",
                "small" => "images/site/default/small/oe2gq279qr2.jpg",
                "thumb" => "images/site/default/thumb/oe2gq279qr2.jpg",
                "xlarge" => "images/site/default/xlarge/oe2gq279qr2.jpg"
              },
              srcset: nil,
              title: "<p>Cialux 1521 + Kurz Luxor 396</p>",
              width: 2020
            },
            hidden: false,
            marked_as_deleted: false,
            type: "picture",
            uid: "1xVLXsKeKyEJlLXro6R7yl"
          },
          description: nil,
          marked_as_deleted: false,
          name: "asset2"
        },
        %Brando.Content.Module.Ref{
          data: %Brando.Villain.Blocks.PictureBlock{
            collapsed: false,
            data: %Brando.Villain.Blocks.PictureBlock.Data{
              alt: nil,
              cdn: false,
              credits: nil,
              dominant_color: "#d8d8d8",
              focal: %Brando.Images.Focal{x: 50, y: 50},
              formats: [:jpg, :webp],
              height: 1854,
              img_class: nil,
              lazyload: false,
              link: nil,
              marked_as_deleted: false,
              media_queries: nil,
              moonwalk: false,
              path: "images/site/default/1r74583pobhb.jpg",
              picture_class: nil,
              placeholder: :svg,
              sizes: %{
                "large" => "images/site/default/large/1r74583pobhb.jpg",
                "medium" => "images/site/default/medium/1r74583pobhb.jpg",
                "micro" => "images/site/default/micro/1r74583pobhb.jpg",
                "small" => "images/site/default/small/1r74583pobhb.jpg",
                "thumb" => "images/site/default/thumb/1r74583pobhb.jpg",
                "xlarge" => "images/site/default/xlarge/1r74583pobhb.jpg"
              },
              srcset: nil,
              title: "<p>Colorplan Claret + Cialux 1521</p>",
              width: 1854
            },
            hidden: false,
            marked_as_deleted: false,
            type: "picture",
            uid: "1xVLXqrZcSM5HdqRL1Tusv"
          },
          description: nil,
          marked_as_deleted: false,
          name: "asset1"
        }
      ],
      sequence: nil,
      vars: nil
    }

    reapplied_block_data = Brando.Villain.reapply_module_data(updated_module, original_block_data)

    [mod_ref1, mod_ref2] = updated_module.refs
    [org_ref1, org_ref2] = original_block_data.refs
    [new_ref1, new_ref2] = reapplied_block_data.refs

    assert mod_ref1.data.type == "media"
    assert mod_ref2.data.type == "media"
    assert mod_ref1.data.__struct__ == Brando.Villain.Blocks.MediaBlock
    assert mod_ref2.data.__struct__ == Brando.Villain.Blocks.MediaBlock
    assert mod_ref1.data.data.__struct__ == Brando.Villain.Blocks.MediaBlock.Data
    assert mod_ref2.data.data.__struct__ == Brando.Villain.Blocks.MediaBlock.Data
    assert org_ref1.data.type == "picture"
    assert org_ref2.data.type == "picture"
    assert org_ref1.data.__struct__ == Brando.Villain.Blocks.PictureBlock
    assert org_ref2.data.__struct__ == Brando.Villain.Blocks.PictureBlock
    assert org_ref1.data.data.__struct__ == Brando.Villain.Blocks.PictureBlock.Data
    assert org_ref2.data.data.__struct__ == Brando.Villain.Blocks.PictureBlock.Data
    assert new_ref1.data.type == "picture"
    assert new_ref2.data.type == "picture"
    assert new_ref1.data.__struct__ == Brando.Villain.Blocks.PictureBlock
    assert new_ref2.data.__struct__ == Brando.Villain.Blocks.PictureBlock
    assert new_ref1.data.data.__struct__ == Brando.Villain.Blocks.PictureBlock.Data
    assert new_ref2.data.data.__struct__ == Brando.Villain.Blocks.PictureBlock.Data

    assert new_ref1.data.data.path == org_ref1.data.data.path
    assert new_ref1.data.data.sizes == org_ref1.data.data.sizes
    assert org_ref1.data.data.placeholder == :svg
    assert new_ref1.data.data.placeholder == :dominant_color
  end
end
