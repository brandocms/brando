defmodule Brando.Migrations.Brando255ClearRefVideoPreloadFalseTest do
  # Runs the upgrade template inside the sandbox transaction, over module
  # and block refs holding the Lazy load Off the module editor stored on
  # every save (#4011).
  use Brando.ConnCase

  import Brando.MigrationTemplates

  alias Brando.Content
  alias Brando.Content.Blocks
  alias Brando.Content.Definitions.Release
  alias Brando.Factory
  alias Brando.Pages.Page

  @template "brando_255_clear_ref_video_preload_false.exs"
  @tenant "tenant_acme_staging"
  @sibling "tenant_acme_preview"

  @off %{preload: false, autoplay: false, loop: false, muted: false, controls: false}

  setup do
    user = Factory.insert(:random_user)

    {:ok, module} =
      Content.create_module(
        Factory.params_for(:module, %{
          code: "{% ref refs.clip %}",
          refs: [
            ref("clip", "video", @off),
            ref("lazy", "video", %{preload: true}),
            ref("unset", "video", %{}),
            ref("media", "media", %{available_blocks: ["video"], template_video: @off})
          ]
        }),
        user
      )

    # A block copies the module's refs when it is made
    module.id |> Blocks.build_module_block(user.id, nil, Page, :module) |> Repo.insert!()

    %{user: user, module: module}
  end

  defp ref(name, type, data), do: %{name: name, uid: Brando.Utils.generate_uid(), data: %{type: type, data: data}}

  # The video settings of every ref in `prefix`, by owner and name
  defp settings(prefix) do
    for [owner, name, data] <-
          rows(
            ~s{SELECT CASE WHEN module_id IS NULL THEN 'block' ELSE 'module' END, name, data FROM "#{prefix}".content_refs}
          ),
        into: %{} do
      video = if data["type"] == "media", do: data["data"]["template_video"], else: data["data"]
      {{owner, name}, Map.take(video, ~w(preload autoplay loop muted controls))}
    end
  end

  defp assert_cleared(prefix) do
    settings = settings(prefix)

    for owner <- ~w(module block) do
      kept = %{"autoplay" => false, "loop" => false, "muted" => false, "controls" => false}
      assert settings[{owner, "clip"}] == Map.put(kept, "preload", nil)
      assert settings[{owner, "media"}] == Map.put(kept, "preload", nil)
      assert settings[{owner, "lazy"}]["preload"] == true
      assert settings[{owner, "unset"}]["preload"] == nil
    end
  end

  defp assert_untouched(prefix) do
    settings = settings(prefix)
    assert settings[{"module", "clip"}]["preload"] == false
    assert settings[{"block", "media"}]["preload"] == false
  end

  test "clears false in module and block refs, in public and every environment", %{module: module} do
    create_environment(@tenant)
    copy_tables("public", @tenant, ["content_refs"], true)
    # An environment without the table
    create_environment(@sibling)

    version = up(@template)

    assert_cleared("public")
    assert_cleared(@tenant)

    # Nothing to restore: a cleared value is any other nil
    down(@template, version)
    assert_cleared("public")

    up(@template)
    assert_cleared("public")

    # The schema reads what it wrote
    clip = module |> Repo.reload!() |> Repo.preload(:refs) |> Map.fetch!(:refs) |> Enum.find(&(&1.name == "clip"))
    assert %{preload: nil, loop: false} = clip.data.data
  end

  test "a run for one environment leaves the others alone" do
    create_environment(@tenant)
    create_environment(@sibling)
    copy_tables("public", @tenant, ["content_refs"], true)
    copy_tables("public", @sibling, ["content_refs"], true)

    up(@template, prefix: @tenant)

    assert_cleared(@tenant)
    assert_untouched(@sibling)
    assert_untouched("public")
  end

  describe "a block made from the module after the upgrade" do
    setup %{user: user, module: module} do
      up(@template)
      # The deploy that runs the upgrade restarts the node, and its module cache
      Brando.Cache.Query.evict_all(Brando.Content.Module)

      %{refs: refs} =
        module.id
        |> Blocks.build_module_block(user.id, nil, Page, :module)
        |> Ecto.Changeset.apply_changes()

      %{clip: Enum.find(refs, &(&1.name == "clip"))}
    end

    # The main `<video>`'s `src` and `data-src`, not the `<noscript>` one's
    defp sources(module, clip, video) do
      block = %{
        type: :module,
        module_id: module.id,
        uid: Brando.Utils.generate_uid(),
        vars: [],
        refs: [%{clip | video_id: video.id, video: video}]
      }

      [video] =
        [%{block: block}] |> Brando.Villain.parse(%Page{}) |> Floki.parse_fragment!() |> Floki.find("[data-video]")

      {video |> Floki.attribute("src") |> List.first(), video |> Floki.attribute("data-src") |> List.first()}
    end

    test "renders lazy with nothing stored anywhere, and eager when the video says so", c do
      assert c.clip.data.data.preload == nil
      url = "https://example.com/video.mp4"

      assert sources(c.module, c.clip, Factory.insert(:external_file_video, creator: c.user)) == {nil, url}

      assert sources(c.module, c.clip, Factory.insert(:external_file_video, creator: c.user, preload: false)) ==
               {url, nil}
    end
  end

  # A release's definition is compared with what was last applied here by
  # baseline digests, which read nil and false alike
  describe "a module from release definitions with Lazy load Off in its file" do
    @definition ~S'''
    defmodule Example.Clip do
      use Brando.Content.Definition
      uid "clip-release"
      name en: "Clip"
      namespace en: "Sections"
      class "clip"

      refs do
        ref :clip, :video do
          config preload: false
        end

        ref :visual, :media do
          config available_blocks: ["video"], template_video: %{preload: false}
        end
      end

      template :heex, ~S"<section><.ref block={@block} ref={:clip} /></section>"
    end
    '''

    setup %{user: user} do
      path = Path.join(System.tmp_dir!(), "brando-255-#{System.unique_integer([:positive])}")
      File.mkdir_p!(path)
      File.write!(Path.join(path, "clip.exs"), @definition)
      on_exit(fn -> File.rm_rf!(path) end)

      assert {:ok, _} = Release.apply(:all, path: path, version: "1.0.0", user: user.id)
      %{path: path}
    end

    defp release_preloads do
      rows(
        "SELECT r.name, r.data #> '{data,preload}', r.data #> '{data,template_video,preload}' FROM content_refs r " <>
          "JOIN content_modules m ON m.id = r.module_id WHERE m.uid = 'clip-release' ORDER BY r.name"
      )
    end

    defp actions(report), do: Enum.map(report.items, &{&1.action, &1.state})

    test "is lazy after the upgrade, in sync, and the next release changing it applies its Off again", c do
      assert release_preloads() == [["clip", false, nil], ["visual", nil, false]]

      up(@template)
      assert release_preloads() == [["clip", nil, nil], ["visual", nil, nil]]
      assert {:ok, report} = Release.plan(path: c.path, version: "1.0.0")
      assert actions(report) == [noop: :in_sync]

      # A later change to another field is an update, not a conflict
      File.write!(Path.join(c.path, "clip.exs"), String.replace(@definition, ~s(class "clip"), ~s(class "clip-2")))
      assert {:ok, report} = Release.plan(path: c.path, version: "1.1.0")
      assert actions(report) == [update: :changed_in_release]

      assert {:ok, _} = Release.apply(:all, path: c.path, version: "1.1.0", user: c.user.id)
      assert release_preloads() == [["clip", false, nil], ["visual", nil, false]]
    end
  end
end
