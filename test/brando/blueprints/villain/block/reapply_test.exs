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
              placeholder: nil,
              text: "Text"
            },
            active: true,
            type: "header",
            uid: "1xVOR77rLseKd3RMm0m1Pl"
          },
          description: nil,
          name: "h2"
        }
      ],
      vars: []
    }

    original_block = %Brando.Content.Block{
      collapsed: false,
      children: [],
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
            active: true,
            type: "header",
            uid: "1xVOTDOvPTUEMeOC6xlunJ"
          },
          description: nil,
          name: "h2"
        }
      ],
      sequence: nil,
      vars: [],
      active: true,
      type: :module,
      uid: "1xVOTDOushEIQlh7sIihqo"
    }

    # TODO: test reapplying a ref
  end

  test "reapply multiple refs and vars" do
    updated_module = %Module{
      class: "entrance subidentity_dupl",
      code:
        "<article b-tpl=\"entrance insight\"{% if wide %} class=\"wide\"{% endif %} style=\"--bg: {{ bg_color }}; --fg: {{ fg_color }}\" data-moonwalk-section data-moonwalk-stage=\"scaleup\">\n  <div class=\"inner\">\n    <a href=\"{{ link_url }}\">\n      <div class=\"bg\" data-moonwalk>\n        {% ref refs.pic %}\n      </div>\n      <div class=\"heading\" data-moonwalk=\"u\">\n        {% ref refs.h2 %}\n      </div>\n    </a>\n  </div>\n</article>",
      deleted_at: nil,
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
              placeholder: nil,
              text: "Text"
            },
            active: true,
            type: "header",
            uid: "1xVOR77rLseKd3RMm0m1Pl"
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
              dominant_color: nil,
              focal: nil,
              formats: [:original, :webp, :avif],
              height: nil,
              img_class: "img-class",
              lazyload: true,
              link: nil,
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
            active: true,
            type: "picture",
            uid: "1xVOQeu7m5g2KqKRCsVaGn"
          },
          description: nil,
          name: "pic"
        }
      ],
      sequence: 2,
      svg: nil,
      updated_at: ~N[2022-02-14 12:35:37],
      vars: [
        %Var{
          type: :boolean,
          important: true,
          instructions: nil,
          key: "wide",
          label: "Is it wide?",
          placeholder: nil,
          value_boolean: false
        },
        %Var{
          type: :color,
          important: true,
          instructions: nil,
          key: "bg_color",
          label: "Background color",
          color_opacity: true,
          color_picker: false,
          palette_id: nil,
          placeholder: nil,
          value: "#000000"
        }
      ],
      wrapper: false
    }

    original_block = %Brando.Content.Block{
      uid: "1xVOTDOushEIQlh7sIihqo",
      refs: [
        %Ref{
          name: "h2",
          description: nil,
          data: %Blocks.HeaderBlock{
            uid: "1xVOTDOvPTUEMeOC6xlunJ",
            type: "header",
            active: true,
            collapsed: false,
            data: %Blocks.HeaderBlock.Data{
              level: 2,
              class: nil,
              id: nil,
              placeholder: nil,
              text: "Photography"
            }
          }
        },
        %Ref{
          name: "pic",
          description: nil,
          data: %Brando.Villain.Blocks.PictureBlock{
            uid: "1xVOTDOvSKu2TQIN3ddD3S",
            type: "picture",
            active: true,
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
            }
          }
        }
      ],
      vars: [
        %Var{
          key: "wide",
          label: "Wide?",
          type: :boolean,
          value_boolean: true,
          important: true,
          instructions: nil,
          placeholder: nil
        },
        %Var{
          key: "bg_color",
          label: "Background color",
          type: :color,
          value: "#FF00FF",
          color_opacity: false,
          color_picker: true,
          palette_id: nil,
          important: true,
          instructions: nil,
          placeholder: nil
        }
      ],
      sequence: nil,
      children: [],
      active: true,
      type: :module,
      collapsed: false
    }

    # TODO: test
  end

  test "media block" do
    updated_module = %Brando.Content.Module{
      class: "2 assets gutter",
      code:
        "<article b-tpl=\"2 assets\" class=\"gutter\">\n  <div class=\"inner\" data-moonwalk-section>\n    <div class=\"asset\" data-moonwalk=\"u\">\n      {% ref refs.asset1 %}\n    </div>\n    <div class=\"asset\" data-moonwalk=\"u\">\n      {% ref refs.asset2 %}\n    </div>\n  </div>\n</article>",
      deleted_at: nil,
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
            active: true,
            type: "media",
            uid: "1xTkuCvHo0eJGOmZ2Tjvd3"
          },
          description: nil,
          name: "asset2"
        },
        %Brando.Content.Module.Ref{
          data: %Brando.Villain.Blocks.MediaBlock{
            collapsed: false,
            data: %Brando.Villain.Blocks.MediaBlock.Data{
              available_blocks: ["picture", "video", "svg"],
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
            active: true,
            type: "media",
            uid: "1xTktiszs3EAefrkah8P70"
          },
          description: nil,
          name: "asset1"
        }
      ],
      sequence: 14,
      svg: nil,
      updated_at: ~N[2022-02-10 15:31:01],
      vars: nil,
      wrapper: false
    }

    original_block = %Brando.Content.Block{
      children: [],
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
            active: true,
            type: "picture",
            uid: "1xVLXsKeKyEJlLXro6R7yl"
          },
          description: nil,
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
            active: true,
            type: "picture",
            uid: "1xVLXqrZcSM5HdqRL1Tusv"
          },
          description: nil,
          name: "asset1"
        }
      ],
      sequence: nil,
      vars: nil
    }

    # TODO: test
  end
end
