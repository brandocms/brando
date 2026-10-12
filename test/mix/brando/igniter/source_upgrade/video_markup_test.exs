defmodule Mix.Brando.Igniter.SourceUpgrade.VideoMarkupTest do
  use ExUnit.Case, async: false

  import Igniter.Test

  alias Mix.Brando.Igniter.SourceUpgrade.VideoMarkup

  @smart_video_path "assets/frontend/js/modules/SmartVideo/index.js"

  # Lett's SmartVideo module before 0.55, trimmed: `boot()` reads `data-src`
  # from the `<video>` found inside the `[data-smart-video]` wrapper.
  @smart_video """
  import { Dom, Events, gsap } from '@brandocms/jupiter'

  export default class SmartVideo {
    constructor(app, el) {
      this.app = app
      this.el = el
      this.video = Dom.find(this.el, '[data-video]')
    }

    boot() {
      const dataSrc = this.video.getAttribute('data-src')
      this.video.src = dataSrc
    }
  }
  """

  defp scan(files), do: [files: files] |> test_project() |> VideoMarkup.warn_video_data_src_reads()

  test "names each line that reads data-src in a script that handles videos" do
    igniter = scan(%{@smart_video_path => @smart_video})

    assert [warning] = igniter.warnings
    assert warning =~ "#{@smart_video_path}:11: const dataSrc = this.video.getAttribute('data-src')"
    assert warning =~ "`data-src` sits on the `[data-smart-video]`"
    assert warning =~ "el.closest('[data-smart-video]').dataset.src"
    assert warning =~ "stay muted"
    assert_unchanged(igniter)
  end

  test "matches double quotes, dataset reads, TypeScript and Svelte" do
    files = %{
      "assets/frontend/js/video.ts" => ~s|const src = video.getAttribute("data-src")\n|,
      "assets/frontend/src/Hero.svelte" => "<script>\n  const src = videoEl.dataset.src\n</script>\n"
    }

    assert [warning] = scan(files).warnings
    assert warning =~ "assets/frontend/js/video.ts:1:"
    assert warning =~ "assets/frontend/src/Hero.svelte:2:"
  end

  test "leaves scripts without videos, fallbacks, dependencies, build output and the admin alone" do
    fallback = """
    // smart video
    const dataSrc = this.video.getAttribute('data-src') || this.el.getAttribute('data-src')
    const wrapped = this.video.closest('[data-smart-video]').dataset.src
    """

    files = %{
      "assets/frontend/js/lazyload.js" => "const src = img.getAttribute('data-src')\n",
      "assets/frontend/js/fallback.js" => fallback,
      "assets/frontend/js/srcset.js" => "// video\nconst set = video.dataset.srcset\n",
      "assets/frontend/node_modules/lib/video.js" => @smart_video,
      "assets/frontend/dist/video.js" => @smart_video,
      "assets/frontend/js/vendor/video.js" => @smart_video,
      "assets/frontend/js/player.min.js" => @smart_video,
      "assets/backend/src/video.js" => @smart_video,
      "lib/my_app/video.js" => @smart_video
    }

    assert scan(files).warnings == []
  end

  test "walks the project's assets on disk, skipping node_modules and the admin" do
    root = Path.join(System.tmp_dir!(), "brando-video-markup-#{System.unique_integer([:positive])}")

    for path <- [@smart_video_path, "assets/frontend/node_modules/lib/video.js", "assets/backend/src/video.js"] do
      File.mkdir_p!(Path.dirname(Path.join(root, path)))
      File.write!(Path.join(root, path), @smart_video)
    end

    try do
      [warning] = File.cd!(root, fn -> VideoMarkup.warn_video_data_src_reads(Igniter.new()).warnings end)
      assert warning =~ "#{@smart_video_path}:11:"
      refute warning =~ "node_modules"
      refute warning =~ "assets/backend"
    after
      File.rm_rf!(root)
    end
  end

  test "mix brando.migrate55 warns" do
    igniter = [app_name: :legacy_app, files: %{@smart_video_path => @smart_video}] |> test_project()
    igniter = Mix.Tasks.Brando.Migrate55.igniter(igniter)

    assert Enum.any?(igniter.warnings, &(&1 =~ "#{@smart_video_path}:11:"))
  end
end
