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
  alias Vix.Vips.Operation

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

  # Each ref's bytes, at /img/<ref>
  defp serve(bodies), do: WebhookReceiver.start(fn %{path: "/img/" <> ref} -> {200, Map.fetch!(bodies, ref)} end)

  defp boxed(id, fills, width, height),
    do: Map.put(layer(id, fills), "absoluteBoundingBox", %{"x" => 0, "y" => 0, "width" => width, "height" => height})

  # Noise in sRGB, which hardly compresses: `bands` 4 has an alpha channel
  defp noise(width, height, bands \\ 3, sigma \\ 40.0) do
    channels =
      for _band <- 1..bands do
        {:ok, channel} = Operation.gaussnoise(width, height, mean: 128.0, sigma: sigma)
        {:ok, channel} = Operation.cast(channel, :VIPS_FORMAT_UCHAR)
        channel
      end

    {:ok, joined} = Operation.bandjoin(channels)
    {:ok, picture} = Operation.copy(joined, interpretation: :VIPS_INTERPRETATION_sRGB)
    picture
  end

  # Noise in shades of gray: as few colours as its spread gives
  defp gray_noise(width, height, sigma) do
    gray = noise(width, height, 1, sigma)
    {:ok, joined} = Operation.bandjoin([gray, gray, gray])
    {:ok, picture} = Operation.copy(joined, interpretation: :VIPS_INTERPRETATION_sRGB)
    picture
  end

  defp png(picture), do: Picture.write!(picture, :memory, suffix: ".png")
  defp jpeg(picture), do: Picture.write!(picture, :memory, suffix: ".jpg", quality: 95)

  defp kb(bytes), do: "#{Float.round(bytes / 1_000, 1)} kB"

  # The default image config's size limit, and the types it takes
  defp put_size_limit(limit, types \\ nil) do
    config = Application.get_env(:brando, Brando.Images, [])

    default =
      config[:default_config]
      |> Map.put(:size_limit, limit)
      |> then(&if(types, do: Map.put(&1, :allowed_mimetypes, types), else: &1))

    put_test_env(Brando.Images, Keyword.put(config, :default_config, default))
  end

  defp stored_path(image), do: Path.join(Brando.Tenant.Storage.current_media_root(), image.path)

  defp figma_tmp_dirs, do: Path.wildcard(Path.join(System.tmp_dir!(), "brando-figma-*"))

  defp gif(picture), do: Picture.write!(picture, :memory, suffix: ".gif")

  # A JPEG stored on its side, with an EXIF orientation that shows it upright
  defp exif_rotated_jpeg(picture) do
    {:ok, picture} = Vix.Vips.Image.mutate(picture, &Vix.Vips.MutableImage.set(&1, "orientation", :gint, 6))
    jpeg(picture)
  end

  defp put_downloader(function),
    do:
      put_test_env(
        Brando.Figma,
        Keyword.put(Application.get_env(:brando, Brando.Figma, []), :downloader, {__MODULE__, function})
      )

  defp download(url, path, limit), do: Brando.Images.Intake.download(url, path, limit, too_large: :size)

  @doc "A download whose scaled-down copy cannot be written: a directory is where it goes."
  def download_with_unwritable_copy(url, path, limit) do
    result = download(url, path, limit)
    for format <- ~w(png jpg gif webp), do: File.mkdir_p!("#{path}-fitted.#{format}")
    result
  end

  @doc """
  A download. The second and later fail unless the first image's original is
  deleted once that image is stored.
  """
  def download_after_first_stored(url, path, limit) do
    dir = Path.dirname(path)
    first = Path.join(dir, "0")
    result = download(url, path, limit)

    cond do
      path == first ->
        File.write!(first <> ".done", "")
        result

      eventually?(fn -> File.exists?(first <> ".done") and not File.exists?(first) end) ->
        result

      true ->
        {:error, "The first image's original was kept."}
    end
  end

  defp eventually?(check, tries \\ 200) do
    cond do
      check.() ->
        true

      tries == 0 ->
        false

      true ->
        Process.sleep(10)
        eventually?(check, tries - 1)
    end
  end

  defp import!(tenant, token, args \\ %{}) do
    assert %{"structuredContent" => result} = call(tenant, token, "import_images", Map.put(args, "url", @link))
    result
  end

  # The images imported here, not the users' avatars
  defp images,
    do: Brando.Repo.all(from(i in Image, where: is_nil(i.deleted_at) and like(i.path, "%figma/%"), order_by: :id))

  test "the tools are offered, and say that they reach Figma", %{tenant: tenant, token: token} do
    %{"result" => %{"tools" => tools}} = rpc(tenant, token, "tools/list") |> json_response(200)
    by_name = Map.new(tools, &{&1["name"], &1["annotations"]})

    assert %{"readOnlyHint" => true, "openWorldHint" => true} = by_name["brando_figma_read_frame"]
    assert %{"readOnlyHint" => true, "openWorldHint" => true} = by_name["brando_figma_status"]

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
                   "images" => [
                     %{
                       "node_id" => "1:11",
                       "image_ref" => "ref-a",
                       "x" => 240,
                       "y" => 160,
                       "width" => 480,
                       "height" => 640
                     }
                   ]
                 },
                 # The same picture as the hero's
                 %{"index" => 1, "kind" => "image", "images" => [%{"node_id" => "1:20", "image_ref" => "ref-a"}]},
                 %{"index" => 2, "kind" => "image"}
               ]
             } = result
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

      # A layer's picture is its shown fill's ref: 5:2 and 5:3 show the same one
      assert top["image_ref"] == "new"
      assert [%{"images" => [%{"image_ref" => "c"}]}, %{"images" => [%{"image_ref" => "c"}]}] = tl(sections)
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

      assert_receive {:webhook_request, %{path: "/img/p"}}
      refute_received {:webhook_request, %{path: "/img/p"}}

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
      assert %Image{focal: %{x: 50, y: 54, mode: :position}} = Brando.Repo.get!(Image, id)

      # An editor moves it, which sets it back to the centre reading; a later
      # import of a crop leaves it
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
      assert %Image{focal: %{x: 10, y: 20, mode: :center}} = Brando.Repo.get!(Image, id)
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
      assert %Image{width: 10, height: 30, focal: %{x: 50, y: 0, mode: :position}} = Brando.Repo.get!(Image, id)
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
      assert %Image{width: 30, height: 10, focal: %{x: 0, y: 50, mode: :position}} = Brando.Repo.get!(Image, id)
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

      assert %{"isError" => true, "content" => [%{"text" => "Figma refused: the token's owner cannot open" <> _}]} =
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

  describe "the token's expiry" do
    setup %{tenant: tenant, user: user} do
      :ok = MCP.put_figma_token(tenant, @token, user)
      :ok
    end

    defp expires_in(tenant, user, days),
      do: :ok = MCP.put_figma_token(tenant, @token, user, expires_on: Date.add(Brando.Figma.today(), days))

    test "read_frame and import_images carry a note in its last seven days, for the tool to pass on",
         %{tenant: tenant, token: token, user: user, receiver: receiver} do
      stub_figma(receiver)

      expires_in(tenant, user, 8)
      assert %{"structuredContent" => result} = call(tenant, token, "read_frame", %{"url" => @link})
      refute Map.has_key?(result, "token_note")
      refute Map.has_key?(import!(tenant, token), "token_note")

      expires_in(tenant, user, 7)
      assert %{"structuredContent" => %{"token_note" => note}} = call(tenant, token, "read_frame", %{"url" => @link})
      assert note =~ "The site's Figma token expires on #{Date.add(Brando.Figma.today(), 7)}, in 7 days."
      assert note =~ "Tell the person: An administrator replaces it"
      assert %{"token_note" => ^note} = import!(tenant, token)

      expires_in(tenant, user, 0)

      assert %{"structuredContent" => %{"token_note" => "The site's Figma token expires today" <> _}} =
               call(tenant, token, "read_frame", %{"url" => @link})
    end

    test "a date that has passed does not stop a call: Figma decides",
         %{tenant: tenant, token: token, receiver: receiver} do
      Brando.Repo.update_all(MCP.Setting, set: [figma_token_expires_on: Date.add(Brando.Figma.today(), -3)])
      stub_figma(receiver)

      assert %{"structuredContent" => %{"frame" => _} = result} = call(tenant, token, "read_frame", %{"url" => @link})
      refute Map.has_key?(result, "token_note")
    end

    test "is from today on, replaced with the token, and cleared when it is removed", %{tenant: tenant, user: user} do
      today = Brando.Figma.today()

      assert {:error, :invalid_expiry} =
               MCP.put_figma_token(tenant, "figd_other-token-9999", user, expires_on: Date.add(today, -1))

      assert {:error, :invalid_expiry} = MCP.put_figma_token(tenant, "figd_other-token-9999", user, expires_on: "soon")
      assert {:ok, @token} = MCP.figma_token(tenant)

      :ok = MCP.put_figma_token(tenant, @token, user, expires_on: today)
      assert %{expires_on: ^today} = MCP.figma_token_status(tenant)

      # A token saved without a date has none recorded, not the old one
      :ok = MCP.put_figma_token(tenant, @token, user)
      assert %{expires_on: nil} = MCP.figma_token_status(tenant)

      expires_in(tenant, user, 30)
      :ok = MCP.delete_figma_token(tenant, user)
      assert Brando.Repo.one(from(s in MCP.Setting, select: s.figma_token_expires_on)) == nil
    end
  end

  describe "brando_figma_status" do
    defp status(tenant, token) do
      assert %{"structuredContent" => result} = call(tenant, token, "status", %{})
      refute Map.has_key?(result, "error")
      result
    end

    defp stub_me(status, body) do
      test = self()

      ReqTest.stub(Brando.Figma, fn conn ->
        send(test, {:figma, conn.request_path, Plug.Conn.get_req_header(conn, "x-figma-token")})
        conn |> Plug.Conn.put_status(status) |> ReqTest.json(body)
      end)
    end

    test "without a token says so, as an answer rather than an error", %{tenant: tenant, token: token} do
      assert %{"token_set" => false, "message" => "No Figma token is set" <> _} = result = status(tenant, token)
      refute Map.has_key?(result, "state")
      refute_received {:figma, _, _}

      # The connection's live page names the step
      assert inspect(BrandoAdmin.Components.ToolSteps.label("status", %{}, %{})) =~ "Checked the site's Figma token"
    end

    test "a valid token: the account's handle and the recorded expiry, never the token, its hint or an email",
         %{tenant: tenant, token: token, user: user} do
      expires_on = Date.add(Brando.Figma.today(), 60)
      :ok = MCP.put_figma_token(tenant, @token, user, expires_on: expires_on)
      stub_me(200, %{"id" => "42", "handle" => "Ada Designer", "email" => "ada@example.com", "img_url" => "https://x"})

      result = status(tenant, token)

      assert %{"token_set" => true, "state" => "valid", "handle" => "Ada Designer", "expires_on" => iso} = result
      assert iso == Date.to_iso8601(expires_on)
      assert result["message"] =~ "It belongs to the Figma account “Ada Designer”."
      assert result["message"] =~ "It expires on #{iso}"
      assert_received {:figma, "/v1/me", [@token]}

      encoded = Jason.encode!(result)
      refute encoded =~ "ada@example.com"
      refute encoded =~ @token
      refute encoded =~ "abcd"
    end

    test "an expired or invalid token, with Figma's words", %{tenant: tenant, token: token, user: user} do
      :ok = MCP.put_figma_token(tenant, @token, user)

      stub_me(401, %{"status" => 401, "err" => "Token has expired"})

      assert %{"state" => "expired", "figma_error" => "Token has expired", "expires_on" => nil, "message" => message} =
               status(tenant, token)

      assert message =~ "has expired. An administrator replaces it"
      assert message =~ "No expiry date was recorded"

      stub_me(403, %{"status" => 403, "err" => "Invalid token"})
      assert %{"state" => "invalid", "figma_error" => "Invalid token", "message" => message} = status(tenant, token)
      assert message =~ "Figma said: “Invalid token”."
    end

    test "a token that may not read its own account could not be checked, and may still read files",
         %{tenant: tenant, token: token, user: user} do
      :ok = MCP.put_figma_token(tenant, @token, user)
      err = "Invalid scope(s): file_content:read. This endpoint requires the current_user:read scope"
      stub_me(403, %{"status" => 403, "err" => err})

      assert %{"token_set" => true, "state" => "no_account_scope", "figma_error" => ^err, "message" => message} =
               result = status(tenant, token)

      refute Map.has_key?(result, "handle")
      assert message =~ "could not be checked"
      assert message =~ "current_user:read"
      assert message =~ "It may still read files"
      refute message =~ "does not accept"
      refute message =~ "expired"
    end

    test "Figma not answering is not an invalid token", %{tenant: tenant, token: token, user: user} do
      :ok = MCP.put_figma_token(tenant, @token, user)

      for status <- [429, 502] do
        stub_me(status, %{"status" => status, "err" => "Invalid token"})
        assert %{"state" => "unreachable", "message" => "Figma could not be reached" <> _} = status(tenant, token)
      end
    end

    test "warns in the token's last days, and says when the recorded date has passed",
         %{tenant: tenant, token: token, user: user} do
      today = Brando.Figma.today()
      :ok = MCP.put_figma_token(tenant, @token, user, expires_on: Date.add(today, 3))
      stub_me(200, %{"handle" => "Ada"})

      assert status(tenant, token)["message"] =~ "expires on #{Date.add(today, 3)}, in 3 days. It needs replacing"

      Brando.Repo.update_all(MCP.Setting, set: [figma_token_expires_on: Date.add(today, -2)])
      assert %{"state" => "valid", "message" => message} = status(tenant, token)
      assert message =~ "#{Date.add(today, -2)}, has passed, but Figma still accepts it."
    end

    test "a token that no longer decrypts is unreadable, and Figma is not asked",
         %{tenant: tenant, token: token, user: user} do
      :ok = MCP.put_figma_token(tenant, @token, user)
      Brando.Repo.update_all(MCP.Setting, set: [figma_token: Brando.Crypto.encrypt(@token, "another context")])

      assert %{"token_set" => true, "state" => "unreadable", "message" => message} = status(tenant, token)
      assert message =~ "can no longer be decrypted"
      refute_received {:figma, _, _}
    end
  end

  describe "with Figma connected through the site's app" do
    setup %{tenant: tenant, user: user} do
      # A pasted token in its last days: not what calls use now
      :ok = MCP.put_figma_token(tenant, @token, user, expires_on: Date.add(Brando.Figma.today(), 3))
      tenant |> Brando.FigmaOAuthHelpers.app!(user) |> Brando.FigmaOAuthHelpers.connect!(access: "oauth-access")
      :ok
    end

    test "read_frame calls Figma with the connection, and carries no expiry note", %{tenant: tenant, token: token} do
      Brando.FigmaOAuthHelpers.stub_figma(fn "GET", "/v1/files/35BOzFjfvJHJM6Wm50E3wA/nodes", _ ->
        {200, %{"name" => "Shared", "nodes" => %{"2950:4703" => %{"document" => document(), "components" => %{}}}}}
      end)

      assert %{"structuredContent" => result} = call(tenant, token, "read_frame", %{"url" => @link})
      assert result["file_name"] == "Shared"
      refute Map.has_key?(result, "token_note")
      assert_received {:figma, "GET", _, _, %{"authorization" => "Bearer oauth-access", "x-figma-token" => nil}}
    end

    test "import_images calls Figma with the connection for each request, and carries no expiry note",
         %{tenant: tenant, token: token, receiver: receiver} do
      stub_figma(receiver)

      result = import!(tenant, token)
      refute Map.has_key?(result, "token_note")
      assert_received {:figma, "/v1/files/35BOzFjfvJHJM6Wm50E3wA/nodes", []}
      assert_received {:figma, "/v1/files/35BOzFjfvJHJM6Wm50E3wA/images", []}
    end

    test "brando_figma_status says the site is connected, as which account, never a token or a secret",
         %{tenant: tenant, token: token} do
      Brando.FigmaOAuthHelpers.stub_figma(fn "GET", "/v1/me", _ ->
        {200, %{"handle" => "Ada Designer", "email" => "ada@example.com"}}
      end)

      assert %{"structuredContent" => result} = call(tenant, token, "status", %{})

      assert %{
               "credential" => "oauth",
               "oauth" => "connected",
               "token_set" => true,
               "state" => "valid",
               "handle" => "Ada Designer",
               "expires_on" => nil,
               "message" => message
             } = result

      assert message =~ "connected to Figma, as the Figma account “Ada Designer”. Its access renews itself."
      refute message =~ "expires"
      assert_received {:figma, "GET", "/v1/me", _, %{"authorization" => "Bearer oauth-access"}}

      encoded = Jason.encode!(result)

      for secret <- [
            "oauth-access",
            "refresh-1",
            @token,
            "wxyz",
            Brando.FigmaOAuthHelpers.client_secret(),
            "ada@example.com"
          ],
          do: refute(encoded =~ secret)
    end

    test "a connection that needs reconnecting: the status says so, and the tools stop without reaching Figma",
         %{tenant: tenant, token: token} do
      Brando.Repo.update_all(MCP.Setting, set: [figma_oauth_needs_reconnect: true])
      Brando.FigmaOAuthHelpers.stub_figma(fn _, _, _ -> {200, %{}} end)

      assert %{
               "structuredContent" =>
                 %{"credential" => "oauth", "oauth" => "needs_reconnect", "state" => "needs_reconnect"} = result
             } =
               call(tenant, token, "status", %{})

      assert result["message"] =~ "An administrator reconnects Figma"

      assert %{"isError" => true, "content" => [%{"text" => text}]} = call(tenant, token, "read_frame", %{"url" => @link})
      assert text =~ "An administrator reconnects Figma"
      refute_received {:figma, _, _, _, _}
    end

    test "with the app saved but not connected, the pasted token is used, and the status says so",
         %{tenant: tenant, token: token, user: user} do
      :ok = Brando.Figma.OAuth.disconnect(tenant, user)
      stub_me = fn -> Brando.FigmaOAuthHelpers.stub_figma(fn "GET", "/v1/me", _ -> {200, %{"handle" => "Ada"}} end) end
      stub_me.()

      assert %{"structuredContent" => %{"credential" => "token", "oauth" => "app_saved", "state" => "valid"} = result} =
               call(tenant, token, "status", %{})

      assert result["message"] =~ "saved but not connected yet; the tools use the pasted token until it is."
      assert_received {:figma, "GET", "/v1/me", _, %{"x-figma-token" => @token, "authorization" => nil}}
    end
  end

  describe "an image over the site's upload limit" do
    setup %{tenant: tenant, user: user} do
      :ok = MCP.put_figma_token(tenant, @token, user)
      :ok
    end

    test "fails with its name, the limit and its size, and the other images are stored",
         %{tenant: tenant, token: token} do
      big = png(noise(200, 100))
      small = png(Picture.new!(30, 10, color: :red))
      put_size_limit(20_000)

      stub_layers(serve(%{"big" => big, "small" => small}), [layer("30:1", [fill("big")]), layer("30:2", [fill("small")])])

      assert %{"images" => [refused, stored]} = import!(tenant, token)

      assert refused["error"] ==
               ~s[The image "Photo 30:1" (30:1, image ref big) is #{kb(byte_size(big))}, over the site's upload limit of 20.0 kB. ] <>
                 "Call again with fit: true to import a copy scaled down to fit the limit, or ask an administrator to raise it."

      refute Map.has_key?(refused, "asset")
      assert %{"asset" => %{"id" => id}} = stored
      assert [%Image{id: ^id}] = images()
    end

    test "with fit, is a copy within the limit, at least twice its largest use; the others are stored as they are",
         %{tenant: tenant, token: token} do
      big = png(noise(400, 200))
      small = png(Picture.new!(30, 10, color: :red))
      put_size_limit(100_000)

      # Twice the box is 100 by 50: a quarter of the image across
      stub_layers(serve(%{"big" => big, "small" => small}), [
        boxed("31:1", [fill("big")], 50, 25),
        layer("31:2", [fill("small")])
      ])

      tmp = figma_tmp_dirs()
      assert %{"images" => [fitted, as_is]} = import!(tenant, token, %{"fit" => true})
      assert figma_tmp_dirs() -- tmp == []

      assert %{
               "fitted" => %{"original" => %{"width" => 400, "height" => 200}, "stored" => stored_size} = info,
               "applied" => [applied],
               "reused" => false,
               "asset" => %{"id" => id}
             } = fitted

      refute Map.has_key?(info, "format")
      assert %{"width" => width, "height" => height} = stored_size
      assert width >= 100 and width < 400 and abs(width - height * 2) <= 1
      assert applied == "scaled down from 400×200 to #{width}×#{height} to fit the site's upload limit"

      by_id = Map.new(images(), &{&1.id, &1})
      stored = by_id[id]
      assert %Image{width: ^width, height: ^height} = stored
      assert stored.path =~ ~r/\.png$/
      size = File.stat!(stored_path(stored)).size
      # As large as fits: near the limit, not far under it
      assert size <= 100_000 and size > 60_000

      refute Map.has_key?(as_is, "fitted")
      assert File.read!(stored_path(by_id[as_is["asset"]["id"]])) == small

      # Again: the same copy, reused
      assert %{"images" => [%{"asset" => %{"id" => ^id}, "reused" => true, "fitted" => _}, _]} =
               import!(tenant, token, %{"fit" => true})

      assert length(images()) == 2
    end

    test "with fit, an image within the limit is stored byte for byte", %{tenant: tenant, token: token} do
      original = png(noise(200, 100))
      put_size_limit(byte_size(original))
      stub_layers(serve(%{"p" => original}), [boxed("32:1", [fill("p")], 10, 5)])

      assert %{"images" => [entry]} = import!(tenant, token, %{"fit" => true})
      refute Map.has_key?(entry, "fitted")
      assert [stored] = images()
      assert File.read!(stored_path(stored)) == original
    end

    test "with fit, is never enlarged: a PNG that does not fit at its full size is stored as a JPEG",
         %{tenant: tenant, token: token} do
      picture = noise(200, 100)
      original = png(picture)
      jpeg = Picture.write!(picture, :memory, suffix: ".jpg", quality: 95)
      assert byte_size(jpeg) * 1.3 < byte_size(original)
      put_size_limit(round(byte_size(jpeg) * 1.2))

      # The box is twice the image: it needs the full size
      stub_layers(serve(%{"p" => original}), [boxed("33:1", [fill("p")], 400, 200)])

      assert %{"images" => [entry]} = import!(tenant, token, %{"fit" => true})

      assert %{
               "fitted" => %{
                 "original" => %{"width" => 200, "height" => 100},
                 "stored" => %{"width" => 200, "height" => 100},
                 "format" => "JPEG"
               },
               "applied" => ["scaled down from 200×100 to 200×100, as JPEG to fit the site's upload limit"]
             } = entry

      assert [%Image{width: 200, height: 100} = stored] = images()
      assert stored.path =~ ~r/\.jpg$/
      assert <<0xFF, 0xD8, _::binary>> = File.read!(stored_path(stored))
    end

    test "with fit, a transparent PNG that does not fit as a PNG is stored as a WebP",
         %{tenant: tenant, token: token} do
      picture = noise(200, 100, 4)
      original = png(picture)
      webp = Picture.write!(picture, :memory, suffix: ".webp", quality: 95)
      assert byte_size(webp) * 1.3 < byte_size(original)
      put_size_limit(round(byte_size(webp) * 1.2), ["image/jpeg", "image/png", "image/webp"])
      stub_layers(serve(%{"p" => original}), [boxed("34:1", [fill("p")], 400, 200)])

      assert %{"images" => [%{"fitted" => %{"format" => "WebP"}}]} = import!(tenant, token, %{"fit" => true})
      assert [%Image{width: 200, height: 100} = stored] = images()
      assert stored.path =~ ~r/\.webp$/
      assert stored |> stored_path() |> Picture.open!() |> Picture.has_alpha?()
    end

    test "with fit, an image still over the limit at twice its largest use is refused, by that size",
         %{tenant: tenant, token: token} do
      put_size_limit(1_000)

      # Twice the box is half the image
      stub_layers(serve(%{"p" => png(noise(400, 200))}), [boxed("35:1", [fill("p")], 100, 50)])

      assert %{"images" => [%{"error" => error}]} = import!(tenant, token, %{"fit" => true})

      assert error ==
               ~s[The image "Photo 35:1" (35:1, image ref p) is still over the site's upload limit of 1.0 kB scaled down to 200×100, ] <>
                 "twice its largest use in the frame, as JPEG. Ask an administrator to raise the limit."

      assert images() == []
    end

    test "with fit, a cropped use counts by what the whole image needs for the crop to be twice its box",
         %{tenant: tenant, token: token} do
      put_size_limit(1_000)

      # The top left quarter of the image in a box of 50 by 25: the whole
      # image at half its size shows that quarter at 100 by 50
      crop = fill("p", %{"scaleMode" => "STRETCH", "imageTransform" => [[0.5, 0, 0], [0, 0.5, 0]]})
      stub_layers(serve(%{"p" => jpeg(noise(400, 200))}), [boxed("36:1", [crop], 50, 25)])

      assert %{"images" => [%{"error" => error}]} = import!(tenant, token, %{"fit" => true})
      assert error =~ "is still over the site's upload limit of 1.0 kB scaled down to 200×100, twice its largest use"
      refute error =~ "as JPEG"

      # A box larger than the image needs its full size
      stub_layers(serve(%{"p" => jpeg(noise(400, 200))}), [boxed("36:2", [crop], 400, 200)])

      assert %{"images" => [%{"error" => error}]} = import!(tenant, token, %{"fit" => true})
      assert error =~ "scaled down to 400×200, its full size."
    end

    test "with fit, a turned image is fitted and turned", %{tenant: tenant, token: token} do
      put_size_limit(100_000)

      # Turned, the image is 200 by 400; twice the box is half of that
      stub_layers(serve(%{"p" => png(noise(400, 200))}), [boxed("37:1", [fill("p", %{"rotation" => 90})], 50, 100)])

      assert %{"images" => [entry]} = import!(tenant, token, %{"fit" => true})

      assert %{
               "fitted" => %{
                 "original" => %{"width" => 200, "height" => 400},
                 "stored" => %{"width" => width, "height" => height}
               },
               "applied" => ["scaled down from 200×400 to" <> _, "rotated 90°"]
             } = entry

      assert width >= 100 and width < 200 and abs(height - width * 2) <= 1
      assert [%Image{width: ^width, height: ^height} = stored] = images()
      assert File.stat!(stored_path(stored)).size <= 100_000
    end

    test "with fit, an animated image is refused, and the message says why", %{tenant: tenant, token: token} do
      put_size_limit(100)
      stub_layers(serve(%{"anim" => animated_gif()}), [layer("38:1", [fill("anim")])])

      assert %{"images" => [%{"error" => error}]} = import!(tenant, token, %{"fit" => true})

      assert error =~
               ~s[The image "Photo 38:1" (38:1, image ref anim) is over the site's upload limit of 100 bytes, and it is animated]

      assert images() == []
    end

    test "over the import's own download limit, it is refused with that limit, with fit or without",
         %{tenant: tenant, token: token} do
      big = png(noise(200, 100))
      put_size_limit(20_000)
      put_test_env(Brando.Figma, Keyword.put(Application.get_env(:brando, Brando.Figma, []), :fit_download_limit, 30_000))
      stub_layers(serve(%{"big" => big}), [layer("39:1", [fill("big")])])

      assert %{"images" => [%{"error" => error}]} = import!(tenant, token, %{"fit" => true})

      assert error ==
               ~s[The image "Photo 39:1" (39:1, image ref big) is #{kb(byte_size(big))}, over the 30.0 kB the import downloads to scale an image down. ] <>
                 "Ask an administrator to raise the site's upload limit or the import's."

      assert %{"images" => [%{"error" => error}]} = import!(tenant, token)
      assert error =~ "over the site's upload limit of 20.0 kB. It is also over the 30.0 kB the import downloads"
      refute error =~ "fit: true"
    end

    test "with fit, an image over the pixel limit is refused before it is decoded", %{tenant: tenant, token: token} do
      put_size_limit(1_000)
      put_test_env(Brando.Images, Keyword.put(Application.get_env(:brando, Brando.Images, []), :max_pixels, 10_000))
      stub_layers(serve(%{"p" => png(noise(400, 200))}), [layer("40:1", [fill("p")])])

      assert %{"images" => [%{"error" => error}]} = import!(tenant, token, %{"fit" => true})
      assert error == Brando.Images.PixelLimit.error_message()
    end

    test "with fit, the floor counts every use of the image in the frame, not only the layers imported",
         %{tenant: tenant, token: token} do
      put_size_limit(1_000)

      # The thumbnail needs a quarter of the image; the hero, not imported, all of it
      stub_layers(serve(%{"p" => png(noise(400, 200))}), [
        boxed("41:1", [fill("p")], 50, 25),
        boxed("41:2", [fill("p")], 200, 100)
      ])

      assert %{"images" => [%{"layers" => [%{"node_id" => "41:1"}], "error" => error}]} =
               import!(tenant, token, %{"fit" => true, "node_ids" => ["41:1"]})

      assert error =~ "is still over the site's upload limit of 1.0 kB scaled down to 400×200, its full size"
    end

    test "with fit, only the types the site takes are tried: a transparent PNG is not stored as a WebP it does not take",
         %{tenant: tenant, token: token} do
      picture = noise(200, 100, 4)
      original = png(picture)
      webp = Picture.write!(picture, :memory, suffix: ".webp", quality: 95)
      assert byte_size(webp) * 1.3 < byte_size(original)
      limit = round(byte_size(webp) * 1.2)
      put_size_limit(limit)
      stub_layers(serve(%{"p" => original}), [boxed("42:1", [fill("p")], 400, 200)])

      {result, log} = ExUnit.CaptureLog.with_log(fn -> import!(tenant, token, %{"fit" => true}) end)
      assert %{"images" => [%{"error" => error}]} = result

      assert error ==
               ~s[The image "Photo 42:1" (42:1, image ref p) is still over the site's upload limit of #{kb(limit)} scaled down to 200×100, ] <>
                 "its full size. Ask an administrator to raise the limit."

      refute log =~ "Rejected type"
      assert images() == []
    end

    test "with fit, a transparent image no type the site takes can hold is refused with the types it takes",
         %{tenant: tenant, token: token} do
      put_size_limit(1_000)
      transparent = Picture.write!(noise(200, 100, 4), :memory, suffix: ".webp")
      stub_layers(serve(%{"p" => transparent}), [boxed("43:1", [fill("p")], 50, 25)])

      assert %{"images" => [%{"error" => error}]} = import!(tenant, token, %{"fit" => true})

      assert error ==
               ~s[The image "Photo 43:1" (43:1, image ref p) is over the site's upload limit of 1.0 kB, and a copy scaled down would be a WebP, ] <>
                 "which the site does not take: it takes GIF, JPEG and PNG. Ask an administrator to raise the limit."
    end

    test "with fit, a single-frame GIF without transparency is stored as a JPEG", %{tenant: tenant, token: token} do
      # A few shades leave the palette entries to spare, and libvips writes
      # one as transparent: Vix reads the GIF with an alpha band, opaque here.
      # Colour noise drew 254 to 281 colours, and a GIF of one that filled
      # its palette had no alpha band.
      original = gif(gray_noise(200, 100, 1.0))
      assert original |> Picture.from_binary!() |> Picture.has_alpha?()
      jpeg = original |> Picture.from_binary!() |> Picture.flatten!() |> jpeg()
      assert byte_size(jpeg) * 1.3 < byte_size(original)
      put_size_limit(round(byte_size(jpeg) * 1.2))
      stub_layers(serve(%{"p" => original}), [boxed("44:1", [fill("p")], 400, 200)])

      assert %{"images" => [%{"fitted" => %{"format" => "JPEG", "stored" => %{"width" => 200, "height" => 100}}}]} =
               import!(tenant, token, %{"fit" => true})

      assert [%Image{width: 200, height: 100} = stored] = images()
      assert stored.path =~ ~r/\.jpg$/
    end

    test "with fit, the first try in the image's own format is at the scale its bytes suggest, not its full size",
         %{tenant: tenant, token: token} do
      # Noise packs the same at any size, so the first try, at
      # sqrt(limit / bytes) less a margin, fits and is kept
      original = png(noise(400, 200))
      assert byte_size(original) > 100_000
      put_size_limit(100_000)
      stub_layers(serve(%{"p" => original}), [boxed("45:1", [fill("p")], 50, 25)])

      assert %{"images" => [%{"fitted" => %{"stored" => %{"width" => width}}}]} = import!(tenant, token, %{"fit" => true})
      expected = ceil(400 * :math.sqrt(100_000 / byte_size(original)) * 0.95)
      assert abs(width - expected) <= 1
    end

    test "with fit, a download that packs worse than its copy is not stored smaller than fits",
         %{tenant: tenant, token: token} do
      # Saved without compression, far over the limit; as a PNG of its full
      # size it is a few hundred bytes
      {:ok, original} = Operation.pngsave_buffer(Picture.new!(400, 200, color: :red), compression: 0)
      assert byte_size(original) > 200_000
      put_size_limit(100_000)
      stub_layers(serve(%{"p" => original}), [boxed("45:2", [fill("p")], 50, 25)])

      assert %{"images" => [%{"fitted" => %{"stored" => %{"width" => 400, "height" => 200}}}]} =
               import!(tenant, token, %{"fit" => true})
    end

    test "with fit, a 16-bit image with half-transparent pixels keeps its transparency",
         %{tenant: tenant, token: token} do
      # Alpha between 1000 and 26500 of 65535 in every pixel: above 255,
      # and not opaque. The site does not take PNG, so the copy is a WebP,
      # not a JPEG
      {:ok, wide} = Operation.linear(noise(300, 150, 4), [100.0], [1000.0])
      {:ok, wide} = Operation.cast(wide, :VIPS_FORMAT_USHORT)
      {:ok, wide} = Operation.copy(wide, interpretation: :VIPS_INTERPRETATION_RGB16)
      original = png(wide)
      put_size_limit(50_000, ["image/jpeg", "image/webp"])
      assert byte_size(original) > 50_000
      stub_layers(serve(%{"p" => original}), [boxed("45:3", [fill("p")], 20, 10)])

      assert %{"images" => [%{"fitted" => %{"format" => "WebP"}}]} = import!(tenant, token, %{"fit" => true})
    end

    test "each original is deleted once its image is stored, not at the end of the call",
         %{tenant: tenant, token: token} do
      put_downloader(:download_after_first_stored)
      red = png(Picture.new!(30, 10, color: :red))
      blue = png(Picture.new!(30, 10, color: :blue))
      stub_layers(serve(%{"a" => red, "b" => blue}), [layer("46:1", [fill("a")]), layer("46:2", [fill("b")])])

      assert %{"images" => [%{"asset" => _}, %{"asset" => _} = second]} = import!(tenant, token)
      refute Map.has_key?(second, "error")
    end

    test "with fit, a copy that cannot be encoded is refused as such, not as over the limit",
         %{tenant: tenant, token: token} do
      # Transparent, so its copy would be a WebP, and wider than a WebP can be;
      # the site does not take PNG
      put_size_limit(1_000, ["image/jpeg", "image/webp"])
      stub_layers(serve(%{"p" => png(noise(17_000, 2, 4))}), [layer("47:1", [fill("p")])])

      assert %{"images" => [%{"error" => error}]} = import!(tenant, token, %{"fit" => true})

      assert error ==
               ~s[The image "Photo 47:1" (47:1, image ref p) could not be scaled down: the copy could not be encoded.]
    end

    test "with fit, a copy that cannot be written fails that image, and the others are stored",
         %{tenant: tenant, token: token} do
      put_downloader(:download_with_unwritable_copy)
      put_size_limit(100_000)
      small = png(Picture.new!(30, 10, color: :red))

      stub_layers(serve(%{"big" => png(noise(400, 200)), "small" => small}), [
        boxed("48:1", [fill("big")], 50, 25),
        layer("48:2", [fill("small")])
      ])

      tmp = figma_tmp_dirs()
      assert %{"images" => [%{"error" => error}, %{"asset" => %{"id" => id}}]} = import!(tenant, token, %{"fit" => true})

      assert error ==
               ~s[The image "Photo 48:1" (48:1, image ref big) was scaled down, but the copy could not be written to a temporary file.]

      assert figma_tmp_dirs() -- tmp == []
      assert [%Image{id: ^id}] = images()
    end

    test "with fit, a turned copy that comes out over the limit is fitted; without fit it is refused",
         %{tenant: tenant, token: token} do
      # Within the limit as saved, at a low quality; turned, it is written at a high one
      original = Picture.write!(noise(200, 100), :memory, suffix: ".jpg", quality: 50)
      limit = byte_size(original) + 100
      put_size_limit(limit)
      stub_layers(serve(%{"p" => original}), [boxed("49:1", [fill("p", %{"rotation" => 90})], 25, 50)])

      assert %{"images" => [%{"error" => _}]} = import!(tenant, token)
      assert images() == []

      assert %{"images" => [entry]} = import!(tenant, token, %{"fit" => true})

      assert %{
               "fitted" => %{
                 "original" => %{"width" => 100, "height" => 200},
                 "stored" => %{"width" => width, "height" => height}
               },
               "applied" => ["scaled down from 100×200 to" <> _, "rotated 90°"]
             } = entry

      assert width >= 50 and width < 100 and abs(height - width * 2) <= 1
      assert [%Image{width: ^width, height: ^height} = stored] = images()
      assert File.stat!(stored_path(stored)).size <= limit
    end

    test "with fit, an image turned by its EXIF orientation is fitted upright", %{tenant: tenant, token: token} do
      # 400 by 200 as stored, 200 by 400 as shown
      original = exif_rotated_jpeg(noise(400, 200))
      put_size_limit(div(byte_size(original), 2))
      stub_layers(serve(%{"p" => original}), [boxed("50:1", [fill("p")], 50, 100)])

      assert %{
               "images" => [
                 %{
                   "fitted" => %{
                     "original" => %{"width" => 200, "height" => 400},
                     "stored" => %{"width" => width, "height" => height}
                   }
                 }
               ]
             } = import!(tenant, token, %{"fit" => true})

      assert width >= 100 and width < 200 and abs(height - width * 2) <= 1
      assert [%Image{width: ^width, height: ^height} = stored] = images()
      file = stored |> stored_path() |> Picture.open!()
      assert {Picture.width(file), Picture.height(file)} == {width, height}
      assert Vix.Vips.Image.header_value(file, "orientation") in [{:ok, 1}, {:error, "No such field"}]
    end

    test "with fit, a portrait image is fitted by both its sides", %{tenant: tenant, token: token} do
      put_size_limit(100_000)
      stub_layers(serve(%{"p" => png(noise(200, 400))}), [boxed("51:1", [fill("p")], 25, 50)])

      assert %{"images" => [%{"fitted" => %{"stored" => %{"width" => width, "height" => height}}}]} =
               import!(tenant, token, %{"fit" => true})

      assert width >= 50 and width < 200 and abs(height - width * 2) <= 1
      assert [%Image{width: ^width, height: ^height} = stored] = images()
      assert File.stat!(stored_path(stored)).size <= 100_000
    end

    test "with fit, a layer that fits the image in its box counts by the side the image fills",
         %{tenant: tenant, token: token} do
      put_size_limit(1_000)

      # A box of 50 by 50 shows the image at 50 by 25
      stub_layers(serve(%{"p" => png(noise(400, 200))}), [boxed("52:1", [fill("p", %{"scaleMode" => "FIT"})], 50, 50)])

      assert %{"images" => [%{"error" => error}]} = import!(tenant, token, %{"fit" => true})
      assert error =~ "scaled down to 100×50, twice its largest use"
    end

    test "fit is true or false", %{tenant: tenant, token: token, receiver: receiver} do
      stub_figma(receiver)

      assert %{"isError" => true, "content" => [%{"text" => "fit is true or false."}]} =
               call(tenant, token, "import_images", %{"url" => @link, "fit" => "yes"})
    end
  end

  describe "with group authorization" do
    setup %{tenant: tenant} do
      put_test_env(:authorization_mode, :groups)
      put_test_env(:tenancy_mode, :none)
      Brando.Authorization.Boundary.put_scope(nil)
      owner = Brando.Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
      member = Brando.Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{}) |> enable_two_factor()
      {:ok, _} = Brando.Authorization.Migration.run()
      :ok = MCP.put_figma_token(tenant, @token, owner)
      %{owner: owner, member: member, scope: Brando.Authorization.Scope.standalone(owner)}
    end

    test "a person who may create images but not update them gets a new image's focal point from the crop",
         %{tenant: tenant} = c do
      keys = ["brando.admin.access", "brando.mcp.connect", "brando.images.read", "brando.images.create"]
      {:ok, group} = Brando.Authorization.Groups.create(c.scope, %{name: "Figma creators"}, keys)
      {:ok, :ok} = Brando.Authorization.Groups.add_member(c.scope, group.id, c.member.id)
      token = connect_directly(c.member, tenant)["access_token"]

      crop = fill("p", %{"scaleMode" => "STRETCH", "imageTransform" => [[1, 0, 0], [0, 0.3635, 0.3453]]})
      stub_layers(pictures(), [layer("9:1", [crop])])

      assert %{"images" => [%{"applied" => ["focal point from the Figma crop"], "asset" => %{"id" => id}}]} =
               import!(tenant, token)

      assert %Image{focal: %{x: 50, y: 54, mode: :position}} = Brando.Repo.get!(Image, id)
    end

    test "a person who may not read the library's copy of a picture imports their own; read_frame names a copy only to whoever may read it",
         %{tenant: tenant} = c do
      keys = ["brando.admin.access", "brando.mcp.connect", "brando.images.create"]
      {:ok, group} = Brando.Authorization.Groups.create(c.scope, %{name: "Figma uploaders"}, keys)
      {:ok, :ok} = Brando.Authorization.Groups.add_member(c.scope, group.id, c.member.id)
      member = connect_directly(c.member, tenant)["access_token"]
      owner = connect_directly(enable_two_factor(c.owner), tenant)["access_token"]
      stub_layers(pictures(), [layer("9:1", [fill("p")])])

      [owners] = asset_ids(import!(tenant, owner))
      assert %{"images" => [%{"reused" => false}]} = result = import!(tenant, member)
      [members] = asset_ids(result)
      assert members != owners

      assert assets(read!(tenant, member)) == %{"9:1" => nil}
      assert assets(read!(tenant, owner)) == %{"9:1" => owners}

      Brando.Repo.soft_delete!(Brando.Repo.get!(Image, owners))
      assert assets(read!(tenant, owner)) == %{"9:1" => members}
      assert assets(read!(tenant, member)) == %{"9:1" => nil}
    end
  end

  describe "read_frame's library image for each layer" do
    setup %{tenant: tenant, user: user} do
      :ok = MCP.put_figma_token(tenant, @token, user)
      :ok
    end

    defp read!(tenant, token, args \\ %{}) do
      assert %{"structuredContent" => result} = call(tenant, token, "read_frame", Map.put(args, "url", @link))
      result
    end

    # Each layer's asset id, or nil
    defp assets(result) do
      for section <- result["sections"], image <- Map.get(section, "images", []), into: %{} do
        {image["node_id"], get_in(image, ["asset", "id"])}
      end
    end

    defp asset_ids(result), do: Enum.map(result["images"], & &1["asset"]["id"])

    test "an upright and a turned layer of one picture each name their own image, imported together or apart",
         %{tenant: tenant, token: token} do
      stub_layers(pictures(), [
        layer("7:1", [fill("p")]),
        layer("7:2", [fill("p", %{"rotation" => 90})]),
        layer("7:3", [fill("q", %{"rotation" => 90})]),
        layer("7:4", [fill("q")])
      ])

      assert assets(read!(tenant, token)) == %{"7:1" => nil, "7:2" => nil, "7:3" => nil, "7:4" => nil}

      # Together; and apart, the turned one first
      [upright, turned] = asset_ids(import!(tenant, token, %{"node_ids" => ["7:1", "7:2"]}))
      [q_turned] = asset_ids(import!(tenant, token, %{"node_ids" => ["7:3"]}))
      assert %{"7:3" => ^q_turned, "7:4" => nil} = assets(read!(tenant, token))
      [q_upright] = asset_ids(import!(tenant, token, %{"node_ids" => ["7:4"]}))

      assert length(Enum.uniq([upright, turned, q_turned, q_upright])) == 4

      assert assets(read!(tenant, token)) == %{"7:1" => upright, "7:2" => turned, "7:3" => q_turned, "7:4" => q_upright}
      assert asset_ids(import!(tenant, token)) == [upright, turned, q_turned, q_upright]
    end

    test "an animated image is stored upright, and a layer showing it turned names that image",
         %{tenant: tenant, token: token} do
      stub_layers(serve(%{"g" => animated_gif()}), [
        layer("7:1", [fill("g")]),
        layer("7:2", [fill("g", %{"rotation" => 90})])
      ])

      assert [id, id] = asset_ids(import!(tenant, token))
      assert assets(read!(tenant, token)) == %{"7:1" => id, "7:2" => id}
    end

    test "an image in the trash is not named; imported again, the copy is, until the first is restored",
         %{tenant: tenant, token: token} do
      stub_layers(pictures(), [layer("7:1", [fill("p")])])
      [first] = asset_ids(import!(tenant, token))
      assert assets(read!(tenant, token)) == %{"7:1" => first}

      Brando.Repo.soft_delete!(Brando.Repo.get!(Image, first))
      assert assets(read!(tenant, token)) == %{"7:1" => nil}

      [copy] = asset_ids(import!(tenant, token))
      assert copy != first
      assert assets(read!(tenant, token)) == %{"7:1" => copy}

      # The oldest again, as the import reuses it
      Brando.Repo.restore!(Brando.Repo.get!(Image, first))
      assert assets(read!(tenant, token)) == %{"7:1" => first}
      assert %{"images" => [%{"reused" => true}]} = result = import!(tenant, token)
      assert asset_ids(result) == [first]
    end

    test "a source that cannot be recorded leaves the import's result whole, for that image and the others",
         %{tenant: tenant, token: token} do
      table = ~s("#{Brando.Tenant.current_prefix() || "public"}".images_sources)

      Brando.Repo.repo().query!("""
      CREATE FUNCTION pg_temp.refuse_b() RETURNS trigger AS $$
      BEGIN IF NEW.ref = 'b' THEN RAISE EXCEPTION 'refused'; END IF; RETURN NEW; END $$ LANGUAGE plpgsql
      """)

      Brando.Repo.repo().query!(
        "CREATE TRIGGER refuse_b BEFORE INSERT ON #{table} FOR EACH ROW EXECUTE FUNCTION pg_temp.refuse_b()"
      )

      stub_layers(pictures(), [layer("7:1", [fill("a")]), layer("7:2", [fill("b")]), layer("7:3", [fill("c")])])

      result = import!(tenant, token)
      assert [_, _, _] = ids = asset_ids(result)
      assert Enum.all?(ids, &is_integer/1)
      refute Enum.any?(result["images"], &Map.has_key?(&1, "error"))

      # Only b's source is missing
      assert %{"7:1" => a, "7:2" => nil, "7:3" => c} = assets(read!(tenant, token))
      assert is_integer(a) and is_integer(c)
    end

    test "every image named on a full frame: pages are measured with the assets, within the limit, none skipped",
         %{tenant: tenant, token: token} do
      layers = for i <- 1..250, do: layer("3:#{i}", [fill("p")])
      stub_layers(pictures(), layers)

      pages = fn ->
        Stream.unfold(0, fn
          nil -> nil
          offset -> (result = read!(tenant, token, %{"offset" => offset})) && {result, result["next_offset"]}
        end)
        |> Enum.to_list()
      end

      before = pages.()
      [id] = asset_ids(import!(tenant, token))
      named = pages.()

      # The assets take room: a page holds fewer sections
      assert length(hd(named)["sections"]) < length(hd(before)["sections"])

      for page <- named do
        assert byte_size(Jason.encode!(page)) <= Brando.MCP.Tools.result_limit()
      end

      indexes = for page <- named, section <- page["sections"], do: section["index"]
      assert indexes == Enum.to_list(0..249)
      assert named |> Enum.map(&assets/1) |> Enum.reduce(&Map.merge/2) |> Map.values() |> Enum.uniq() == [id]
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
