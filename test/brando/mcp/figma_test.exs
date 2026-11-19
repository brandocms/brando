defmodule Brando.MCP.FigmaTest do
  # The Figma tools over the MCP endpoint: the site environment's token, a
  # frame read through Figma's API (stubbed), and its images downloaded
  # through the URL guard (from a local server) into the media library.
  use Brando.LiveCase

  import Brando.MCPHelpers
  import Brando.Test.Support, only: [put_test_env: 2]
  import Ecto.Query, only: [from: 2]

  alias Brando.Activity.Event
  alias Brando.AI.Agent.Guidance
  alias Brando.Images.Image
  alias Brando.MCP
  alias Brando.Media.Folder
  alias Brando.WebhookReceiver
  alias BrandoAdmin.Images.FolderBrowser
  alias Elixir.Image, as: Picture
  alias Req.Test, as: ReqTest

  @png File.read!(Path.expand("../../fixtures/sample.png", __DIR__))
  @link "https://www.figma.com/design/35BOzFjfvJHJM6Wm50E3wA/Shared?node-id=2950-4703"
  @token "figd_test-token-abcd"

  setup %{conn: conn, current_user: user} do
    setup_fetcher()
    enable_two_factor(user)
    tenant = MCP.tenant(nil, nil) |> switch!()
    tokens = connect!(conn, tenant)

    put_test_env(Brando.Figma, req_options: [plug: {Req.Test, Brando.Figma}])
    put_test_env(Brando.Webhooks, allow_localhost: true, resolver: {Brando.WebhookTestResolver, :resolve})

    receiver = WebhookReceiver.start(fn %{path: path} -> if path == "/missing", do: {404, ""}, else: {200, @png} end)

    root = Brando.Tenant.Storage.current_media_root()
    on_exit(fn -> File.rm_rf(Path.join(root, FolderBrowser.absolute_folder("figma", FolderBrowser.upload_root(nil)))) end)

    %{tenant: tenant, token: tokens["access_token"], user: user, receiver: receiver}
  end

  defp call(tenant, token, name, arguments) do
    tenant
    |> rpc(token, "tools/call", %{"name" => "brando_figma_" <> name, "arguments" => arguments})
    |> json_response(200)
    |> Map.fetch!("result")
  end

  defp document do
    %{
      "id" => "2950:4703",
      "name" => "Case – Tipping",
      "type" => "FRAME",
      "layoutMode" => "VERTICAL",
      "absoluteBoundingBox" => %{"x" => 100, "y" => 100, "width" => 1440, "height" => 2000},
      "layoutGrids" => [
        %{"pattern" => "COLUMNS", "alignment" => "STRETCH", "count" => 12, "gutterSize" => 20, "offset" => 40}
      ],
      "children" => [
        %{
          "id" => "1:10",
          "name" => "Hero",
          "type" => "INSTANCE",
          "componentId" => "c1",
          "children" => [
            %{
              "id" => "1:11",
              "name" => "Hero photo",
              "type" => "RECTANGLE",
              "fills" => [image("ref-a")],
              "absoluteBoundingBox" => %{"x" => 340, "y" => 260, "width" => 480, "height" => 640}
            },
            %{"id" => "1:12", "name" => "Title", "type" => "TEXT", "characters" => "Tipping"}
          ]
        },
        # The same picture again, and one Figma has no download for
        %{"id" => "1:20", "name" => "Repeat", "type" => "RECTANGLE", "fills" => [image("ref-a")]},
        %{"id" => "1:30", "name" => "Gone", "type" => "RECTANGLE", "fills" => [image("ref-gone")]}
      ]
    }
  end

  defp image(ref), do: %{"type" => "IMAGE", "imageRef" => ref}

  # Figma's API: the node and the file's image downloads
  defp stub_figma(receiver, opts \\ []) do
    test = self()

    ReqTest.stub(Brando.Figma, fn conn ->
      send(test, {:figma, conn.request_path, Plug.Conn.get_req_header(conn, "x-figma-token")})

      case {opts[:status], conn.request_path} do
        {status, _} when is_integer(status) ->
          Plug.Conn.send_resp(conn, status, "")

        {_, "/v1/files/35BOzFjfvJHJM6Wm50E3wA/nodes"} ->
          ReqTest.json(conn, %{
            "name" => "Shared",
            "nodes" => %{
              "2950:4703" => %{
                "document" => document(),
                "components" => %{"c1" => %{"name" => "Case/Hero"}},
                "componentSets" => %{}
              }
            }
          })

        {_, "/v1/files/35BOzFjfvJHJM6Wm50E3wA/images"} ->
          ReqTest.json(conn, %{
            "meta" => %{
              "images" => %{
                "ref-a" => WebhookReceiver.url(receiver, "/img/a"),
                "ref-gone" => WebhookReceiver.url(receiver, "/missing")
              }
            }
          })
      end
    end)
  end

  # A frame of these layers, with a download for each ref from `receiver`
  # (at /img/<ref>)
  defp stub_layers(receiver, layers, frame_name \\ "Fills") do
    refs = for %{"fills" => fills} <- layers, %{"imageRef" => ref} <- fills, do: ref
    downloads = Map.new(refs, &{&1, WebhookReceiver.url(receiver, "/img/" <> &1)})

    ReqTest.stub(Brando.Figma, fn conn ->
      case conn.request_path do
        "/v1/files/35BOzFjfvJHJM6Wm50E3wA/nodes" ->
          ReqTest.json(conn, %{
            "name" => "Shared",
            "nodes" => %{
              "2950:4703" => %{
                "document" => %{"id" => "2950:4703", "name" => frame_name, "type" => "FRAME", "children" => layers}
              }
            }
          })

        "/v1/files/35BOzFjfvJHJM6Wm50E3wA/images" ->
          ReqTest.json(conn, %{"meta" => %{"images" => downloads}})
      end
    end)
  end

  defp layer(id, fills), do: %{"id" => id, "name" => "Photo #{id}", "type" => "RECTANGLE", "fills" => fills}

  defp fill(ref, attrs \\ %{}), do: Map.merge(%{"type" => "IMAGE", "imageRef" => ref, "scaleMode" => "FILL"}, attrs)

  # A distinct picture per ref, wider than tall, with a mark in one corner
  # so that each turn of it is another file
  defp pictures do
    WebhookReceiver.start(fn %{path: "/img/" <> ref} ->
      color = Enum.at([:red, :green, :blue, :yellow, :purple, :orange], :erlang.phash2(ref, 6))
      picture = 30 |> Elixir.Image.new!(10, color: color) |> Elixir.Image.Draw.rect!(0, 0, 4, 4, color: :white)
      {200, Elixir.Image.write!(picture, :memory, suffix: ".png")}
    end)
  end

  # Two frames of 30 by 10
  defp animated_gif do
    frames = [Picture.new!(30, 10, color: :red), Picture.new!(30, 10, color: :blue)]
    {:ok, joined} = Vix.Vips.Operation.arrayjoin(frames, across: 1)
    {:ok, joined} = Vix.Vips.Image.mutate(joined, &Vix.Vips.MutableImage.set(&1, "page-height", :gint, 10))
    Picture.write!(joined, :memory, suffix: ".gif")
  end

  defp import!(tenant, token, args \\ %{}) do
    assert %{"structuredContent" => result} = call(tenant, token, "import_images", Map.put(args, "url", @link))
    result
  end

  # The images imported here, not the users' avatars
  defp images,
    do: Brando.Repo.all(from(i in Image, where: is_nil(i.deleted_at) and like(i.path, "%figma/%"), order_by: :id))

  test "both tools are offered, and say that they reach Figma", %{tenant: tenant, token: token} do
    %{"result" => %{"tools" => tools}} = rpc(tenant, token, "tools/list") |> json_response(200)
    by_name = Map.new(tools, &{&1["name"], &1["annotations"]})

    assert %{"readOnlyHint" => true, "openWorldHint" => true} = by_name["brando_figma_read_frame"]

    assert %{"readOnlyHint" => false, "destructiveHint" => false, "openWorldHint" => true} =
             by_name["brando_figma_import_images"]
  end

  test "without a token, a tool says who adds one", %{tenant: tenant, token: token} do
    assert %{"isError" => true, "content" => [%{"text" => "Figma is not connected" <> _}]} =
             call(tenant, token, "read_frame", %{"url" => @link})
  end

  describe "with the site's token" do
    setup %{tenant: tenant, user: user} do
      :ok = MCP.put_figma_token(tenant, @token, user)
      :ok
    end

    test "read_frame outlines the frame", %{tenant: tenant, token: token, receiver: receiver} do
      stub_figma(receiver)

      assert %{"structuredContent" => result} = call(tenant, token, "read_frame", %{"url" => @link})
      assert_received {:figma, "/v1/files/35BOzFjfvJHJM6Wm50E3wA/nodes", [@token]}

      assert %{
               "file_name" => "Shared",
               "frame" => %{
                 "name" => "Case – Tipping",
                 "width" => 1440,
                 "height" => 2000,
                 "layout_grids" => [
                   %{"pattern" => "columns", "alignment" => "stretch", "count" => 12, "gutter" => 20, "margin" => 40}
                 ]
               },
               "sections_total" => 3,
               "next_offset" => nil,
               "sections" => [
                 %{
                   "index" => 0,
                   "component" => "Case/Hero",
                   "texts" => [%{"text" => "Tipping"}],
                   "images" => [%{"node_id" => "1:11", "x" => 240, "y" => 160, "width" => 480, "height" => 640}]
                 },
                 %{"index" => 1, "kind" => "image", "images" => [%{"node_id" => "1:20"}]},
                 %{"index" => 2, "kind" => "image"}
               ]
             } = result

      refute Jason.encode!(result) =~ "ref-a"
    end

    test "import_images stores each picture once, in the frame's folder, and reuses it after",
         %{tenant: tenant, token: token, receiver: receiver} do
      stub_figma(receiver)

      assert %{"structuredContent" => result} = call(tenant, token, "import_images", %{"url" => @link})

      assert %{"folder" => "figma/case-tipping", "distinct_images" => 2, "next_offset" => nil} = result

      # One entry per picture, with the layers that show it
      assert [
               %{
                 "asset" => %{"kind" => "image", "id" => id},
                 "reused" => false,
                 "layers" => [%{"node_id" => "1:11", "section" => 0}, %{"node_id" => "1:20", "section" => 1}]
               },
               %{"layers" => [%{"node_id" => "1:30"}], "error" => "Figma's download answered 404."}
             ] = result["images"]

      assert [%Image{id: ^id, folder_id: folder_id, path: path}] = images()
      assert %Folder{name: "case-tipping"} = Brando.Repo.get!(Folder, folder_id)
      assert path =~ "/figma/case-tipping/"

      # Again: nothing new
      assert %{"structuredContent" => %{"images" => [%{"asset" => %{"id" => ^id}, "reused" => true} | _]}} =
               call(tenant, token, "import_images", %{"url" => @link, "node_ids" => ["1:11"]})

      assert length(images()) == 1

      assert Brando.Repo.repo().exists?(
               from(e in Event,
                 where: e.source == :mcp and fragment("?->>'tool'", e.details) == "brando_figma_import_images"
               )
             )
    end

    test "the connection's live page hears each import: its images, new or reused, and their folder",
         %{tenant: tenant, token: token, receiver: receiver} do
      stub_figma(receiver)
      grant = Brando.Repo.one!(Brando.MCP.Grant)
      Brando.MCP.Watch.subscribe(grant.id)

      call(tenant, token, "import_images", %{"url" => @link})
      assert_receive {Brando.MCP.Watch, %{state: :ok, tool: "brando_figma_import_images", details: first}}
      [%Image{id: id}] = images()

      assert %{
               "folder" => "figma/case-tipping",
               "images" => [%{"id" => ^id, "reused" => false}],
               "failed" => 1,
               "output" => %{"frame" => "Case – Tipping", "images" => 1}
             } = first

      call(tenant, token, "import_images", %{"url" => @link, "node_ids" => ["1:11"]})
      assert_receive {Brando.MCP.Watch, %{state: :ok, details: %{"images" => [%{"id" => ^id, "reused" => true}]} = again}}
      refute Map.has_key?(again, "failed")
    end

    test "a changed image is stored next to the first, even when the config overwrites",
         %{tenant: tenant, token: token, receiver: receiver} do
      config = Application.get_env(:brando, Brando.Images)

      put_test_env(
        Brando.Images,
        Keyword.put(config, :default_config, %Brando.Type.ImageConfig{
          Brando.Type.ImageConfig.default_config()
          | overwrite: true,
            random_filename: false
        })
      )

      stub_figma(receiver)

      %{"structuredContent" => %{"images" => [%{"asset" => %{"id" => first}} | _]}} =
        call(tenant, token, "import_images", %{"url" => @link, "node_ids" => ["1:11"]})

      # The picture changed in Figma: same layer, same name, other bytes
      changed = 12 |> Elixir.Image.new!(12, color: :red) |> Elixir.Image.write!(:memory, suffix: ".png")
      other = WebhookReceiver.start(fn _ -> {200, changed} end)
      stub_figma(other)

      %{"structuredContent" => %{"images" => [%{"asset" => %{"id" => second}, "reused" => false} | _]}} =
        call(tenant, token, "import_images", %{"url" => @link, "node_ids" => ["1:11"]})

      assert first != second
      [one, two] = images()
      assert one.path != two.path
      root = Brando.Tenant.Storage.current_media_root()
      assert File.read!(Path.join(root, one.path)) == @png
    end

    test "read_frame's first page carries the guidance for building from Figma",
         %{tenant: tenant, token: token, user: user, receiver: receiver} do
      put_test_env(Brando.Figma,
        req_options: [plug: {Req.Test, Brando.Figma}],
        guidance: "Developers: header and footer are page chrome."
      )

      MCP.in_tenant(tenant, fn ->
        {:ok, _} = Guidance.save("The frame's top text is heading and intro.", user, kind: :figma)
        {:ok, _} = Guidance.save("Not for Figma.", user)
      end)

      stub_figma(receiver)

      assert %{"structuredContent" => %{"guidance" => guidance, "sections" => [_ | _]}} =
               call(tenant, token, "read_frame", %{"url" => @link})

      assert %{
               "developers" => "Developers: header and footer are page chrome.",
               "administrators" => "The frame's top text is heading and intro.",
               "about" => about
             } = guidance

      assert about =~ "grants no permissions"

      # Later pages carry none
      assert %{"structuredContent" => later} = call(tenant, token, "read_frame", %{"url" => @link, "offset" => 1})
      refute Map.has_key?(later, "guidance")
    end

    test "long guidance leaves the first page fewer sections, within the result limit",
         %{tenant: tenant, token: token, user: user} do
      MCP.in_tenant(tenant, fn ->
        {:ok, _} = Guidance.save(String.duplicate("g", 12_000), user, kind: :figma)
      end)

      texts =
        for i <- 1..40,
            do: %{"id" => "2:#{i}", "name" => "T#{i}", "type" => "TEXT", "characters" => String.duplicate("x", 400)}

      ReqTest.stub(Brando.Figma, fn conn ->
        ReqTest.json(conn, %{
          "name" => "Shared",
          "nodes" => %{
            "2950:4703" => %{
              "document" => %{"id" => "2950:4703", "name" => "Long", "type" => "FRAME", "children" => texts}
            }
          }
        })
      end)

      assert %{"structuredContent" => first} = result = call(tenant, token, "read_frame", %{"url" => @link})
      refute result["isError"]
      # The guidance comes whole: the page's last sections made room for it,
      # where cutting the guidance beside a full page would leave about 6 KB
      assert String.length(first["guidance"]["administrators"]) == 12_000
      assert byte_size(Jason.encode!(first)) <= 24_000

      assert %{"structuredContent" => second} =
               call(tenant, token, "read_frame", %{"url" => @link, "offset" => first["next_offset"]})

      assert Enum.map(first["sections"] ++ second["sections"], & &1["index"]) == Enum.to_list(0..39)
      assert second["next_offset"] == nil
    end

    # Guidance never shortens a section: a large first section keeps all its
    # images beside long guidance, whatever its characters encode to
    for {name, guidance} <- [
          multibyte: String.duplicate("見出し", 4_000),
          quotes: String.duplicate(~s("), 12_000),
          latin: String.duplicate("g", 12_000)
        ] do
      test "a large first section keeps all its images beside long guidance (#{name})",
           %{tenant: tenant, token: token, user: user} do
        MCP.in_tenant(tenant, fn ->
          {:ok, _} = Guidance.save(unquote(guidance), user, kind: :figma)
        end)

        gallery =
          for i <- 1..40 do
            %{
              "id" => "4:#{i}",
              "name" => "Gallery image #{i} – detail of the façade, seen from the street",
              "type" => "RECTANGLE",
              "fills" => [image("ref-#{i}")],
              "absoluteBoundingBox" => %{"x" => 0, "y" => i * 600, "width" => 800, "height" => 600}
            }
          end

        texts =
          for i <- 1..20,
              do: %{"id" => "2:#{i}", "name" => "T#{i}", "type" => "TEXT", "characters" => String.duplicate("x", 400)}

        children = [%{"id" => "4:0", "name" => "Gallery", "type" => "INSTANCE", "children" => gallery} | texts]

        ReqTest.stub(Brando.Figma, fn conn ->
          ReqTest.json(conn, %{
            "name" => "Shared",
            "nodes" => %{
              "2950:4703" => %{
                "document" => %{"id" => "2950:4703", "name" => "Long", "type" => "FRAME", "children" => children}
              }
            }
          })
        end)

        pages =
          Stream.unfold(0, fn
            nil ->
              nil

            offset ->
              result = call(tenant, token, "read_frame", %{"url" => @link, "offset" => offset})
              refute result["isError"], inspect(result["content"])
              page = result["structuredContent"]
              assert byte_size(Jason.encode!(page)) <= 24_000
              # Every page moves on
              assert page["next_offset"] == nil or page["next_offset"] > offset
              {page, page["next_offset"]}
          end)
          |> Enum.to_list()

        [first | later] = pages
        assert %{"administrators" => administrators} = first["guidance"]
        assert administrators != ""
        assert String.starts_with?(unquote(guidance), administrators)
        refute Enum.any?(later, &Map.has_key?(&1, "guidance"))

        sections = Enum.flat_map(pages, & &1["sections"])
        assert Enum.map(sections, & &1["index"]) == Enum.to_list(0..20)
        refute Enum.any?(sections, &Map.has_key?(&1, "images_left_out"))
        refute Enum.any?(sections, &Map.has_key?(&1, "texts_left_out"))

        node_ids = for section <- sections, image <- section["images"], do: image["node_id"]
        assert node_ids == for(i <- 1..40, do: "4:#{i}")
      end
    end

    test "a section too large for a page keeps what fits and says how much it left out",
         %{tenant: tenant, token: token} do
      texts =
        for i <- 1..60,
            do: %{"id" => "2:#{i}", "name" => "T#{i}", "type" => "TEXT", "characters" => String.duplicate("x", 600)}

      ReqTest.stub(Brando.Figma, fn conn ->
        ReqTest.json(conn, %{
          "name" => "Shared",
          "nodes" => %{
            "2950:4703" => %{
              "document" => %{
                "id" => "2950:4703",
                "name" => "Long",
                "type" => "FRAME",
                "children" => [%{"id" => "2:0", "name" => "Body", "type" => "INSTANCE", "children" => texts}]
              }
            }
          }
        })
      end)

      assert %{"structuredContent" => %{"sections" => [section], "next_offset" => nil}} =
               call(tenant, token, "read_frame", %{"url" => @link})

      assert section["texts_left_out"] > 0
      assert length(section["texts"]) + section["texts_left_out"] == 60
      assert %{"shortened" => true} = hd(section["texts"])
    end

    test "a placeholder shown by many layers is one entry, its layers capped",
         %{tenant: tenant, token: token, receiver: receiver} do
      layers =
        for i <- 1..250,
            do: %{"id" => "3:#{i}", "name" => "Card #{i}", "type" => "RECTANGLE", "fills" => [image("ref-a")]}

      test = self()

      ReqTest.stub(Brando.Figma, fn conn ->
        send(test, :figma)

        case conn.request_path do
          "/v1/files/35BOzFjfvJHJM6Wm50E3wA/nodes" ->
            ReqTest.json(conn, %{
              "name" => "Shared",
              "nodes" => %{
                "2950:4703" => %{
                  "document" => %{"id" => "2950:4703", "name" => "Grid", "type" => "FRAME", "children" => layers}
                }
              }
            })

          "/v1/files/35BOzFjfvJHJM6Wm50E3wA/images" ->
            ReqTest.json(conn, %{"meta" => %{"images" => %{"ref-a" => WebhookReceiver.url(receiver, "/img/a")}}})
        end
      end)

      assert %{"structuredContent" => %{"images" => [entry], "distinct_images" => 1}} =
               call(tenant, token, "import_images", %{"url" => @link})

      assert length(entry["layers"]) == 10
      assert entry["layers_left_out"] == 240
      assert %{"kind" => "image"} = entry["asset"]
    end

    test "stacked fills: an opaque top fill hides the ones under it, which are not imported",
         %{tenant: tenant, token: token} do
      stub_layers(pictures(), [
        layer("5:1", [fill("old"), fill("new")]),
        layer("5:2", [
          fill("a"),
          fill("b", %{"scaleMode" => "FIT"}),
          fill("c", %{"scaleMode" => "STRETCH", "imageTransform" => [[1, 0, 0], [0, 1, 0]]})
        ]),
        layer("5:3", [fill("c"), fill("gone", %{"visible" => false})])
      ])

      assert %{"structuredContent" => %{"sections" => sections}} = call(tenant, token, "read_frame", %{"url" => @link})

      assert [
               %{"images" => [%{"node_id" => "5:1", "hidden_fills" => [%{"image_ref" => "old"}]} = top]},
               %{
                 "images" => [
                   %{
                     "node_id" => "5:2",
                     "scale_mode" => "crop",
                     "hidden_fills" => [%{"image_ref" => "a"}, %{"image_ref" => "b"}]
                   }
                 ]
               },
               %{"images" => [%{"node_id" => "5:3"} = plain]}
             ] = sections

      refute Map.has_key?(top, "image_ref")
      refute Map.has_key?(plain, "hidden_fills")

      result = import!(tenant, token)
      assert result["distinct_images"] == 2

      assert [%{"layers" => [%{"node_id" => "5:1"}]}, %{"layers" => [%{"node_id" => "5:2"}, %{"node_id" => "5:3"}]}] =
               result["images"]

      assert length(images()) == 2
    end

    test "a translucent stack shows, and imports, every image in it, each layer once per asset",
         %{tenant: tenant, token: token} do
      stub_layers(pictures(), [
        layer("6:1", [
          fill("hidden"),
          fill("base"),
          fill("soft", %{"opacity" => 0.4}),
          fill("soft", %{"blendMode" => "MULTIPLY"})
        ])
      ])

      assert %{"structuredContent" => %{"sections" => [section]}} = call(tenant, token, "read_frame", %{"url" => @link})
      assert length(section["images"]) == 3
      assert section["note"] =~ "shows 3 images"

      assert %{"distinct_images" => 2, "images" => [base, soft]} = import!(tenant, token)
      assert [%{"node_id" => "6:1"}] = base["layers"]
      assert [%{"node_id" => "6:1"}] = soft["layers"]
      assert length(images()) == 2
    end

    test "a turned image is imported as a turned copy, reused for the same turn",
         %{tenant: tenant, token: token} do
      # Figma's 90 is a quarter turn clockwise
      stub_layers(pictures(), [
        layer("7:1", [fill("p", %{"rotation" => 90})]),
        layer("7:2", [fill("p")]),
        layer("7:3", [fill("p", %{"rotation" => 180})]),
        layer("7:4", [fill("p", %{"rotation" => -90})]),
        layer("7:5", [fill("p", %{"rotation" => -270})])
      ])

      assert %{"distinct_images" => 4, "images" => [turned, upright, half, three]} = import!(tenant, token)

      assert %{
               "rotation" => 90,
               "applied" => ["rotated 90°"],
               "reused" => false,
               "layers" => [%{"node_id" => "7:1"}, %{"node_id" => "7:5"}]
             } = turned

      refute Map.has_key?(upright, "rotation")
      refute Map.has_key?(upright, "applied")
      assert %{"rotation" => 180, "applied" => ["rotated 180°"]} = half
      assert %{"rotation" => 270, "applied" => ["rotated 270°"]} = three

      by_id = Map.new(images(), &{&1.id, &1})
      assert %{width: 10, height: 30} = by_id[turned["asset"]["id"]]
      assert %{width: 30, height: 10} = by_id[upright["asset"]["id"]]
      assert %{width: 30, height: 10} = by_id[half["asset"]["id"]]
      assert %{width: 10, height: 30} = by_id[three["asset"]["id"]]

      # Turned clockwise: the mark at the top left is now at the top right
      root = Brando.Tenant.Storage.current_media_root()
      stored = Elixir.Image.open!(Path.join(root, by_id[turned["asset"]["id"]].path))
      assert [255, 255, 255 | _] = Elixir.Image.get_pixel!(stored, 9, 0)
      refute match?([255, 255, 255 | _], Elixir.Image.get_pixel!(stored, 0, 0))

      # Again: the same picture turned the same way is the same asset
      id = turned["asset"]["id"]

      assert %{"images" => [%{"asset" => %{"id" => ^id}, "reused" => true, "applied" => ["rotated 90°"]}]} =
               import!(tenant, token, %{"node_ids" => ["7:1"]})

      assert length(images()) == 4
    end

    test "another angle is not applied, and the result says so", %{tenant: tenant, token: token} do
      stub_layers(pictures(), [layer("8:1", [fill("p", %{"rotation" => 12.5})])])

      assert %{
               "images" => [
                 %{"rotation" => 12.5, "not_applied" => ["rotation 12.5°: only quarter turns are applied"]} = entry
               ]
             } =
               import!(tenant, token)

      refute Map.has_key?(entry, "applied")
      assert [%Image{width: 30, height: 10}] = images()
    end

    test "a cropped image gets its focal point from the crop, and a reused one keeps its own",
         %{tenant: tenant, token: token} do
      # The issue's crop: full width, the band from 34.5% to 71% of the height
      crop = fill("p", %{"scaleMode" => "STRETCH", "imageTransform" => [[1, 0, 0], [0, 0.3635, 0.3453]]})
      stub_layers(pictures(), [layer("9:1", [crop])])

      assert %{"images" => [%{"applied" => ["focal point from the Figma crop"], "asset" => %{"id" => id}}]} =
               import!(tenant, token)

      # y: 0.3453 / (1 - 0.3635) = 0.5425 → 54; the full width → 50
      assert %Image{focal: %{x: 50, y: 54}} = Brando.Repo.get!(Image, id)

      # An editor moves it; a later import of a crop leaves it
      {:ok, _image} = Brando.Images.update_image(Brando.Repo.get!(Image, id), %{focal: %{x: 10, y: 20}}, :system)
      other = fill("p", %{"scaleMode" => "STRETCH", "imageTransform" => [[0.5, 0, 0.5], [0, 0.5, 0.5]]})
      stub_layers(pictures(), [layer("9:2", [other])])

      assert %{
               "images" => [
                 %{"reused" => true, "not_applied" => ["focal point from the Figma crop: the library already had" <> _]} =
                   entry
               ]
             } =
               import!(tenant, token)

      refute Map.has_key?(entry, "applied")
      assert %Image{focal: %{x: 10, y: 20}} = Brando.Repo.get!(Image, id)
    end

    test "a rotated crop: the focal point in the turned copy", %{tenant: tenant, token: token} do
      # A quarter turn right, showing the stored image's left half: the
      # turned image's top half
      crop = fill("p", %{"scaleMode" => "STRETCH", "imageTransform" => [[0, 0.5, 0], [-1, 0, 1]]})
      stub_layers(pictures(), [layer("10:1", [crop])])

      assert %{
               "images" => [
                 %{
                   "rotation" => 90,
                   "applied" => ["rotated 90°", "focal point from the Figma crop"],
                   "asset" => %{"id" => id}
                 }
               ]
             } =
               import!(tenant, token)

      # The top half of the turned image: y 0 / (1 - 0.5) = 0; the full width → 50
      assert %Image{width: 10, height: 30, focal: %{x: 50, y: 0}} = Brando.Repo.get!(Image, id)
    end

    test "what was not applied is said for every layer that shows the image, by name",
         %{tenant: tenant, token: token} do
      # Both are the picture upright, one asset: only the second is turned
      # 12.5° and only the second is cropped
      crop = fill("p", %{"scaleMode" => "STRETCH", "imageTransform" => [[0.5, 0, 0.25], [0, 0.5, 0.25]]})

      stub_layers(pictures(), [
        layer("11:1", [fill("p")]),
        layer("11:2", [fill("p", %{"rotation" => 12.5})]),
        layer("11:3", [crop])
      ])

      assert %{"images" => [entry]} = import!(tenant, token)
      assert [%{"node_id" => "11:1"}, %{"node_id" => "11:2"}, %{"node_id" => "11:3"}] = entry["layers"]
      assert [turn, focal] = entry["not_applied"]
      assert turn =~ ~s["Photo 11:2" (11:2)]
      assert turn =~ "rotation 12.5°: only quarter turns are applied"
      assert focal =~ ~s["Photo 11:3" (11:3)]
      assert focal =~ "focal point from the Figma crop"
      refute Map.has_key?(entry, "applied")
    end

    test "a mirrored crop is imported as it is stored, and the result says the mirror was not applied",
         %{tenant: tenant, token: token} do
      mirrored = fill("p", %{"scaleMode" => "STRETCH", "imageTransform" => [[-1, 0, 1], [0, 1, 0]]})
      stub_layers(pictures(), [layer("12:1", [mirrored])])

      assert %{"structuredContent" => %{"sections" => [%{"images" => [image]}]}} =
               call(tenant, token, "read_frame", %{"url" => @link})

      assert image["mirrored"] == true
      refute Map.has_key?(image, "rotation")

      assert %{"images" => [entry]} = import!(tenant, token)
      refute Map.has_key?(entry, "rotation")
      assert ["mirrored in Figma: the image is imported unmirrored"] = entry["not_applied"]

      # The mark stays at the top left
      assert [%Image{width: 30, height: 10} = stored] = images()
      root = Brando.Tenant.Storage.current_media_root()
      assert [255, 255, 255 | _] = root |> Path.join(stored.path) |> Picture.open!() |> Picture.get_pixel!(0, 0)
    end

    test "the folder is the frame's name as a slug, or untitled when no slug is left", %{tenant: tenant, token: token} do
      stub_layers(pictures(), [layer("20:1", [fill("a")])], "2. Prosjekt > Sprekenhus")
      assert %{"folder" => "figma/2-prosjekt-sprekenhus"} = import!(tenant, token)

      stub_layers(pictures(), [layer("20:1", [fill("a")])], "→ / 🎉")
      assert %{"folder" => "figma/untitled"} = import!(tenant, token)
    end

    test "an animated image is not turned: the original is imported and the result says why",
         %{tenant: tenant, token: token} do
      gif = animated_gif()
      receiver = WebhookReceiver.start(fn _request -> {200, gif} end)
      stub_layers(receiver, [layer("13:1", [fill("anim", %{"rotation" => 90})])])

      assert %{"images" => [entry]} = import!(tenant, token)

      assert %{"rotation" => 90, "not_applied" => ["rotated 90°: the image is animated, so it is imported upright"]} =
               entry

      refute Map.has_key?(entry, "applied")

      assert [%Image{width: 30, height: 10} = stored] = images()
      root = Brando.Tenant.Storage.current_media_root()
      frames = root |> Path.join(stored.path) |> Picture.open!(pages: :all)
      assert Picture.pages(frames) == 2
    end

    test "a turned animated image the library refuses is an error on its entry, not a failed call",
         %{tenant: tenant, token: token} do
      gif = animated_gif()
      receiver = WebhookReceiver.start(fn _request -> {200, gif} end)
      stub_layers(receiver, [layer("13:3", [fill("anim", %{"rotation" => 90})])])

      # One frame is within the limit, both together are not.
      original = Application.get_env(:brando, Brando.Images, [])
      put_test_env(Brando.Images, Keyword.put(original, :max_pixels, 400))

      assert %{"images" => [%{"error" => _} = entry]} = import!(tenant, token)
      refute Map.has_key?(entry, "asset")
    end

    test "an animated image cropped turned: the focal point is in the image as stored, upright",
         %{tenant: tenant, token: token} do
      gif = animated_gif()
      receiver = WebhookReceiver.start(fn _request -> {200, gif} end)
      # A quarter turn right, showing the stored image's left half
      crop = fill("anim", %{"scaleMode" => "STRETCH", "imageTransform" => [[0, 0.5, 0], [-1, 0, 1]]})
      stub_layers(receiver, [layer("13:2", [crop])])

      assert %{"images" => [%{"applied" => ["focal point from the Figma crop"], "asset" => %{"id" => id}}]} =
               import!(tenant, token)

      # The left half of the stored image: x 0 / (1 - 0.5) = 0; the full height → 50
      assert %Image{width: 30, height: 10, focal: %{x: 0, y: 50}} = Brando.Repo.get!(Image, id)
    end

    test "a turned JPEG is written at a high quality, not the encoder's default", %{tenant: tenant, token: token} do
      {:ok, noise} = Vix.Vips.Operation.gaussnoise(300, 100, mean: 128.0, sigma: 40.0)
      {:ok, noise} = Vix.Vips.Operation.cast(noise, :VIPS_FORMAT_UCHAR)
      jpeg = Picture.write!(noise, :memory, suffix: ".jpg", quality: 95)
      receiver = WebhookReceiver.start(fn _request -> {200, jpeg} end)
      stub_layers(receiver, [layer("14:1", [fill("j", %{"rotation" => 90})])])

      assert %{"images" => [%{"applied" => ["rotated 90°"]}]} = import!(tenant, token)
      assert [%Image{width: 100, height: 300} = stored] = images()

      root = Brando.Tenant.Storage.current_media_root()
      written = File.stat!(Path.join(root, stored.path)).size
      default = noise |> Picture.rotate!(90) |> Picture.write!(:memory, suffix: ".jpg") |> byte_size()
      assert written > default * 1.3
    end

    test "a Figma refusal is told as such", %{tenant: tenant, token: token, receiver: receiver} do
      stub_figma(receiver, status: 403)

      assert %{"isError" => true, "content" => [%{"text" => "Figma refused the site's token" <> _}]} =
               call(tenant, token, "import_images", %{"url" => @link})

      assert images() == []
    end

    test "a bad link or offset is refused before Figma is called",
         %{tenant: tenant, token: token, receiver: receiver} do
      stub_figma(receiver)
      assert %{"isError" => true} = call(tenant, token, "read_frame", %{"url" => "https://example.com/x"})
      assert %{"isError" => true} = call(tenant, token, "read_frame", %{"url" => @link, "offset" => -1})
      refute_received {:figma, _, _}
    end
  end

  describe "the token" do
    test "is stored encrypted, shown by its last four characters, and removed", %{tenant: tenant, user: user} do
      assert MCP.figma_token_status(tenant) == nil
      assert {:error, :invalid_token} = MCP.put_figma_token(tenant, "short", user)
      assert {:error, :invalid_token} = MCP.put_figma_token(tenant, "has a space in it, so no", user)

      :ok = MCP.put_figma_token(tenant, "  " <> @token <> "\n", user)

      assert {:ok, @token} = MCP.figma_token(tenant)
      assert %{hint: "abcd", set_by: %{id: id}} = MCP.figma_token_status(tenant)
      assert id == user.id
      refute Brando.Repo.one(from(s in MCP.Setting, select: s.figma_token)) =~ @token

      assert %{readable: true} = MCP.figma_token_status(tenant)

      # The endpoint's switch is its own
      assert MCP.enabled?(tenant)

      :ok = MCP.delete_figma_token(tenant, user)
      assert MCP.figma_token(tenant) == :error
      assert MCP.figma_token_status(tenant) == nil
    end

    test "one that no longer decrypts is shown as such, and the tools have none",
         %{tenant: tenant, user: user, token: token} do
      :ok = MCP.put_figma_token(tenant, @token, user)
      # As after a change of the encryption secret
      Brando.Repo.update_all(MCP.Setting, set: [figma_token: Brando.Crypto.encrypt(@token, "another context")])

      assert %{hint: "abcd", readable: false} = MCP.figma_token_status(tenant)

      assert %{"isError" => true, "content" => [%{"text" => "Figma is not connected" <> _}]} =
               call(tenant, token, "read_frame", %{"url" => @link})
    end

    test "only someone who may manage connections sets it", %{tenant: tenant} do
      editor = Brando.Factory.insert(:random_user, role: :editor)
      assert {:error, :forbidden} = MCP.put_figma_token(tenant, @token, editor)
      assert {:error, :forbidden} = MCP.delete_figma_token(tenant, editor)
    end
  end
end
