defmodule Brando.Assets.ConfigTargetTest do
  use ExUnit.Case, async: true

  alias Brando.Assets.ConfigTarget
  alias Brando.Exception.BlueprintError

  defmodule FakeBlueprint do
    def __blueprint__, do: true
    def custom_file_cfg, do: %Brando.Type.FileConfig{upload_path: "files/custom"}
    def custom_image_cfg, do: %{upload_path: "images/custom-function"}
    def custom_video_cfg, do: %{upload_path: "videos/custom-function", upload_strategy: :local}

    def custom_gallery_cfg do
      %{
        image: %{upload_path: "images/custom-gallery"},
        video: %{upload_path: "videos/custom-gallery", upload_strategy: :local}
      }
    end

    def invalid_image_cfg, do: %{upload_path: ""}
    def sentinel_file_cfg, do: :config_target
    def wrong_image_cfg, do: %Brando.Type.FileConfig{}
  end

  describe "schema_module/1" do
    test "resolves existing blueprint modules with and without the Elixir. prefix" do
      assert {:ok, Brando.Pages.Page} = ConfigTarget.schema_module("Brando.Pages.Page")
      assert {:ok, Brando.Pages.Page} = ConfigTarget.schema_module("Elixir.Brando.Pages.Page")
    end

    test "rejects modules that are not blueprints" do
      assert :error = ConfigTarget.schema_module("System")
    end

    test "rejects unknown modules without minting atoms" do
      assert :error = ConfigTarget.schema_module("No.Such.ModuleXyz123")
      assert_raise ArgumentError, fn -> String.to_existing_atom("Elixir.No.Such.ModuleXyz123") end
    end
  end

  describe "config_function!/2" do
    test "calls exported zero-arity functions on blueprints" do
      assert %Brando.Type.FileConfig{upload_path: "files/custom"} =
               ConfigTarget.config_function!(inspect(FakeBlueprint), "custom_file_cfg")
    end

    # Regression: config_target strings arrive from the client (upload intake) —
    # the old Module.concat + String.to_atom + apply let any authenticated user
    # execute arbitrary zero-arity functions ("file:System:function:halt").
    test "refuses functions on non-blueprint modules" do
      assert_raise ArgumentError, ~r/blueprint/, fn ->
        ConfigTarget.config_function!("System", "halt")
      end
    end

    test "refuses functions the blueprint does not export" do
      assert_raise ArgumentError, fn ->
        ConfigTarget.config_function!(inspect(FakeBlueprint), "not_exported_fn")
      end
    end
  end

  describe "resolved_function_config!/3" do
    test "normalizes raw maps into the declared typed config" do
      assert %Brando.Type.ImageConfig{
               upload_path: "images/custom-function",
               sizes: sizes
             } =
               ConfigTarget.resolved_function_config!(
                 :image,
                 inspect(FakeBlueprint),
                 "custom_image_cfg"
               )

      assert map_size(sizes) > 0

      assert %Brando.Type.VideoConfig{
               upload_path: "videos/custom-function",
               upload_strategy: :local
             } =
               ConfigTarget.resolved_function_config!(
                 :video,
                 inspect(FakeBlueprint),
                 "custom_video_cfg"
               )
    end

    test "validates resolved values and rejects a config struct for the wrong media type" do
      assert_raise BlueprintError, ~r/:upload_path expected a non-empty string/, fn ->
        ConfigTarget.resolved_function_config!(
          :image,
          inspect(FakeBlueprint),
          "invalid_image_cfg"
        )
      end

      assert_raise BlueprintError, ~r/matching config struct/, fn ->
        ConfigTarget.resolved_function_config!(
          :image,
          inspect(FakeBlueprint),
          "wrong_image_cfg"
        )
      end

      assert_raise BlueprintError, ~r/matching config struct/, fn ->
        ConfigTarget.resolved_function_config!(
          :file,
          inspect(FakeBlueprint),
          "sentinel_file_cfg"
        )
      end
    end

    test "normalizes both sides of gallery function configs" do
      target = "gallery:#{inspect(FakeBlueprint)}:function:custom_gallery_cfg"

      assert {:ok, %Brando.Type.ImageConfig{upload_path: "images/custom-gallery"}} =
               Brando.Images.get_config_for(target)

      assert {:ok, %Brando.Type.VideoConfig{upload_path: "videos/custom-gallery"}} =
               Brando.Videos.get_config_for(target)
    end
  end

  describe "blueprint_asset/2" do
    test "resolves only declared Blueprint assets" do
      assert {:ok, %{name: :cover, type: :image}} =
               ConfigTarget.blueprint_asset("Brando.BlueprintTest.Project", "cover")

      assert :error = ConfigTarget.blueprint_asset("Brando.BlueprintTest.Project", "title")
      assert :error = ConfigTarget.blueprint_asset("Brando.BlueprintTest.Project", "missing_field")
    end
  end

  describe "typed defaults" do
    test "all media contexts expose typed default configs" do
      assert {:ok, %Brando.Type.ImageConfig{}} = Brando.Images.get_config_for("default")
      assert {:ok, %Brando.Type.FileConfig{}} = Brando.Files.get_config_for("default")
      assert {:ok, %Brando.Type.VideoConfig{}} = Brando.Videos.get_config_for("default")
    end
  end

  describe "serialize/1" do
    test "serializes field and function targets canonically" do
      assert ConfigTarget.serialize({"image", Brando.Pages.Page, :cover}) ==
               "image:Brando.Pages.Page:cover"

      assert ConfigTarget.serialize({:video, Brando.Pages.Page, :function, :video_cfg}) ==
               "video:Brando.Pages.Page:function:video_cfg"
    end

    test "passes strings through and unwraps target maps" do
      assert ConfigTarget.serialize("default") == "default"

      assert ConfigTarget.serialize(%{config_target: "file:Brando.Pages.Page:document"}) ==
               "file:Brando.Pages.Page:document"
    end

    test "rejects unsupported types and non-blueprint modules" do
      assert_raise ArgumentError, fn ->
        ConfigTarget.serialize({:audio, Brando.Pages.Page, :track})
      end

      assert_raise ArgumentError, fn -> ConfigTarget.serialize({:image, System, :cover}) end
    end
  end

  describe "hostile config_target through the upload facade" do
    test "falls back to the default config instead of executing" do
      assert {%Brando.Type.FileConfig{}, "default"} =
               Brando.Uploads.resolve_file_config("file:System:function:halt")

      assert {_cfg, "default"} =
               Brando.Uploads.resolve_image_config("image:System:function:halt")
    end

    test "falls back when function config validation fails" do
      target = "image:#{inspect(FakeBlueprint)}:function:invalid_image_cfg"

      assert {%Brando.Type.ImageConfig{}, "default"} =
               Brando.Uploads.resolve_image_config(target)
    end

    test "rejects field targets whose declared media type does not match" do
      image_target = "image:Brando.BlueprintTest.Project:pdf"
      file_target = "file:Brando.BlueprintTest.Project:cover"
      video_target = "video:Brando.BlueprintTest.Project:cover"

      assert_raise ArgumentError, ~r/resolves to :file/, fn ->
        Brando.Images.get_config_for(image_target)
      end

      assert_raise ArgumentError, ~r/has type :image/, fn ->
        Brando.Files.get_config_for(file_target)
      end

      assert_raise ArgumentError, ~r/has type :image/, fn ->
        Brando.Videos.get_config_for(video_target)
      end

      assert {%Brando.Type.ImageConfig{}, "default"} =
               Brando.Uploads.resolve_image_config(image_target)

      assert {%Brando.Type.FileConfig{}, "default"} =
               Brando.Uploads.resolve_file_config(file_target)

      assert {%Brando.Type.VideoConfig{}, "default"} =
               Brando.Uploads.resolve_video_config(video_target)
    end
  end
end
