defmodule Brando.Assets.ConfigTargetTest do
  use ExUnit.Case, async: true

  alias Brando.Assets.ConfigTarget

  defmodule FakeBlueprint do
    def __blueprint__, do: true
    def custom_file_cfg, do: %Brando.Type.FileConfig{upload_path: "files/custom"}
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
  end
end
