defmodule Brando.Images.ConfigResolverTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Brando.Images.ConfigResolver
  alias Brando.Images.Image

  setup do
    previous = Logger.level()
    Logger.configure(level: :warning)
    on_exit(fn -> Logger.configure(level: previous) end)
  end

  test "an image whose field is gone uses the default config, and says so once per target without the image" do
    target = "image:Brando.Pages.Page:gallery_#{System.unique_integer([:positive])}"
    {:ok, default} = ConfigResolver.get("default")

    log =
      capture_log(fn ->
        for id <- 1..3 do
          assert ConfigResolver.get(%Image{id: id, path: "images/#{id}.jpg", config_target: target}) == {:ok, default}
        end
      end)

    # Other tests log the same warning for their own targets; count only this one's
    assert [_once] = Regex.scan(~r/Images point at .*\(#{Regex.escape(target)}\)/, log)

    assert log =~
             "Images point at a field Brando.Pages.Page no longer has (#{target}); they use the default image config."

    refute log =~ "%Brando.Images.Image{"
    refute log =~ "stacktrace"
  end

  test "stale_target_message/2 counts and says why" do
    assert ConfigResolver.stale_target_message("image:Brando.Pages.Page:gallery", 10) ==
             "10 images point at a field Brando.Pages.Page no longer has (image:Brando.Pages.Page:gallery); they use the default image config."

    assert ConfigResolver.stale_target_message("image:Brando.Pages.Page:meta_image", 1) =~ "1 image points at"

    assert ConfigResolver.stale_target_message("image:MyApp.Gone:cover", 2) ==
             "2 images point at MyApp.Gone, which is no longer a Blueprint (image:MyApp.Gone:cover); they use the default image config."
  end
end
