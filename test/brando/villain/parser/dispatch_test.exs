defmodule Brando.Villain.ParserDispatchTest do
  @moduledoc """
  Every callback in `Brando.Villain.Parser` is overridable, so a site's parser
  can replace any of them. This asserts that the ones Brando calls *internally*
  still land on the site's version.

  They stopped doing so when the implementations moved out of the `__using__`
  quote and into the module body: inside the quote a bare `render_caption(data)`
  meant "the using module's version", in the module body it means "Brando's".
  Nothing warned — a site's override simply became dead code, and pages
  re-rendered with Brando's defaults.
  """
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Content
  alias Brando.Factory

  defmodule Parser do
    @moduledoc false
    use Brando.Villain.Parser

    def render_caption(_data), do: "DISPATCHED_CAPTION"

    def video_file_options(data) do
      [
        width: Map.get(data, :width),
        height: Map.get(data, :height),
        cover: false,
        progress: true,
        play_button: "DISPATCHED_PLAY_BUTTON"
      ]
    end

    def header(data, opts), do: ["DISPATCHED_HEADER", Brando.Villain.Parser.header(data, opts)]
    def html(%{text: text}, _opts), do: "DISPATCHED_HTML:#{text}"
    def svg(%{code: code}, _opts), do: "DISPATCHED_SVG:#{code}"
    def markdown(%{text: text}, _opts), do: "DISPATCHED_MARKDOWN:#{text}"
    def text(%{text: text}, _opts), do: "DISPATCHED_TEXT:#{text}"

    def container(block, opts),
      do: ["DISPATCHED_CONTAINER", Brando.Villain.Parser.container(block, opts)]
  end

  # `picture/2` and `video/2` are not overridden here on purpose: they are the
  # ones that have to call *back* into this module for `render_caption/1` and
  # `video_file_options/1`.

  setup do
    put_test_env(Brando.Villain, extra_blocks: [], parser: Parser)

    user = Factory.insert(:random_user)
    {:ok, %{user: user}}
  end

  defp render_ref(user, code, ref_name, ref_block, type \\ :liquid) do
    module_params =
      Factory.params_for(:module, %{
        type: type,
        code: code,
        refs: [
          %{
            name: ref_name,
            uid: Brando.Utils.generate_uid(),
            data: %{type: ref_block.type, data: %{}}
          }
        ]
      })

    {:ok, module} = Content.create_module(module_params, user)

    block = %{
      block: %{
        type: :module,
        module_id: module.id,
        uid: Brando.Utils.generate_uid(),
        vars: [],
        refs: [
          Map.merge(
            %{name: ref_name, description: nil, uid: Brando.Utils.generate_uid()},
            ref_block.ref
          )
        ]
      }
    }

    Brando.Villain.parse([block], %Brando.Pages.Page{})
  end

  describe "a site's parser overrides" do
    test "are used for text refs", %{user: user} do
      html =
        render_ref(user, "{% ref refs.body %}", "body", %{
          type: "text",
          ref: %{
            data: %Brando.Villain.Blocks.TextBlock{
              type: "text",
              data: %Brando.Villain.Blocks.TextBlock.Data{text: "hi", type: :paragraph}
            }
          }
        })

      assert html =~ "DISPATCHED_TEXT:hi"
    end

    test "are used for refs rendered by HEEx modules", %{user: user} do
      html =
        render_ref(
          user,
          "<.ref block={@block} ref={:body} />",
          "body",
          %{
            type: "text",
            ref: %{
              data: %Brando.Villain.Blocks.TextBlock{
                type: "text",
                data: %Brando.Villain.Blocks.TextBlock.Data{text: "hi", type: :paragraph}
              }
            }
          },
          :heex
        )

      assert html =~ "DISPATCHED_TEXT:hi"
    end

    test "are used for html, svg and markdown refs", %{user: user} do
      assert render_ref(user, "{% ref refs.r %}", "r", %{
               type: "html",
               ref: %{
                 data: %Brando.Villain.Blocks.HtmlBlock{
                   type: "html",
                   data: %Brando.Villain.Blocks.HtmlBlock.Data{text: "<b>x</b>"}
                 }
               }
             }) =~ "DISPATCHED_HTML:<b>x</b>"

      assert render_ref(user, "{% ref refs.r %}", "r", %{
               type: "svg",
               ref: %{
                 data: %Brando.Villain.Blocks.SvgBlock{
                   type: "svg",
                   data: %Brando.Villain.Blocks.SvgBlock.Data{code: "<svg/>"}
                 }
               }
             }) =~ "DISPATCHED_SVG:<svg/>"

      assert render_ref(user, "{% ref refs.r %}", "r", %{
               type: "markdown",
               ref: %{
                 data: %Brando.Villain.Blocks.MarkdownBlock{
                   type: "markdown",
                   data: %Brando.Villain.Blocks.MarkdownBlock.Data{text: "# x"}
                 }
               }
             }) =~ "DISPATCHED_MARKDOWN:# x"
    end

    test "are used for header refs", %{user: user} do
      html =
        render_ref(user, "{% ref refs.title %}", "title", %{
          type: "header",
          ref: %{
            data: %Brando.Villain.Blocks.HeaderBlock{
              type: "header",
              data: %Brando.Villain.Blocks.HeaderBlock.Data{text: "Hello", level: 2}
            }
          }
        })

      assert html =~ "DISPATCHED_HEADER"
      assert html =~ "<h2>Hello</h2>"
    end

    # `header/2`'s anchored clause renders the heading by calling back into
    # `header/2`, so the override has to be reached twice for one heading.
    test "are used by header/2's recursive anchor clause" do
      html = IO.iodata_to_binary(Parser.header(%{text: "Hello", level: 2, anchor: "top"}, %{}))

      assert html =~ ~s(<a name="top"></a>)
      # once for the outer call, once for the inner one it makes itself
      assert html |> String.split("DISPATCHED_HEADER") |> length() == 3
    end

    # `picture/2` builds its caption with `render_caption/1`.
    test "are used for render_caption/1 inside picture/2", %{user: user} do
      image = Factory.insert(:image, creator: user)

      html =
        render_ref(user, "{% ref refs.cover %}", "cover", %{
          type: "picture",
          ref: %{
            image_id: image.id,
            image: image,
            data: %Brando.Villain.Blocks.PictureBlock{
              type: "picture",
              data: %Brando.Villain.Blocks.PictureBlock.Data{}
            }
          }
        })

      assert html =~ "DISPATCHED_CAPTION"
    end

    # The one that broke bielkeyang: the site turned the cover off and the play
    # button on, and got Brando's hardcoded SVG cover and no play button.
    test "are used for video_file_options/1 inside video/2", %{user: user} do
      video = Factory.insert(:external_file_video, creator: user)

      html =
        render_ref(user, "{% ref refs.hero %}", "hero", %{
          type: "video",
          ref: %{
            video_id: video.id,
            video: video,
            data: %Brando.Villain.Blocks.VideoBlock{
              type: "video",
              data: %Brando.Villain.Blocks.VideoBlock.Data{cover: "svg", play_button: false}
            }
          }
        })

      assert html =~ "DISPATCHED_PLAY_BUTTON"
      assert html =~ ~s(data-progress)
      refute html =~ "data-cover"
    end
  end

  describe "container children" do
    test "are rendered through the site's parser", %{user: user} do
      module_params =
        Factory.params_for(:module, %{
          code: "{% ref refs.body %}",
          refs: [
            %{
              name: "body",
              uid: Brando.Utils.generate_uid(),
              data: %{type: "text", data: %{}}
            }
          ]
        })

      {:ok, module} = Content.create_module(module_params, user)

      child = %{
        type: :module,
        module_id: module.id,
        uid: Brando.Utils.generate_uid(),
        vars: [],
        refs: [
          %{
            name: "body",
            description: nil,
            uid: Brando.Utils.generate_uid(),
            data: %Brando.Villain.Blocks.TextBlock{
              type: "text",
              data: %Brando.Villain.Blocks.TextBlock.Data{text: "nested", type: :paragraph}
            }
          }
        ]
      }

      block = %{
        block: %{
          type: :container,
          uid: Brando.Utils.generate_uid(),
          palette_id: nil,
          container_id: nil,
          anchor: nil,
          vars: [],
          refs: [],
          children: [child]
        }
      }

      html = Brando.Villain.parse([block], %Brando.Pages.Page{})

      # the container itself, and the module ref rendered inside it
      assert html =~ "DISPATCHED_CONTAINER"
      assert html =~ "DISPATCHED_TEXT:nested"
    end
  end
end
