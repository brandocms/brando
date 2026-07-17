defmodule Brando.Blueprint.AssetConfigTest do
  use ExUnit.Case, async: true

  alias Brando.Blueprint.Assets
  alias Brando.Exception.BlueprintError

  def provider_completed(video, user) do
    send(Process.whereis(__MODULE__), {:provider_completed, video, user})
  end

  defmodule ConfiguredAssets do
    use Brando.Blueprint,
      application: "Brando",
      domain: "AssetConfigTest",
      schema: "ConfiguredAssets",
      singular: "configured_asset",
      plural: "configured_assets",
      gettext_module: Brando.Gettext

    assets do
      asset :default_image, :image, cfg: :default
      asset :dynamic_image, :image, cfg: fn -> %{upload_path: "images/dynamic"} end
      asset :database_image, :image, cfg: :db
      asset :default_video, :video, cfg: :default
      asset :default_file, :file, cfg: :default
      asset :target_file, :file, cfg: :config_target
    end
  end

  defmodule VideoCallbacks do
    use Brando.Blueprint,
      application: "Brando",
      domain: "AssetConfigTest",
      schema: "VideoCallbacks",
      singular: "video_callback",
      plural: "video_callbacks",
      gettext_module: Brando.Gettext

    assets do
      asset :clip, :video,
        cfg: %{
          completed_callback: &Brando.Blueprint.AssetConfigTest.provider_completed/2
        }
    end
  end

  test "all materialized asset configs are typed and merged with defaults" do
    assets = Map.new(Assets.__assets__(ConfiguredAssets), &{&1.name, &1})

    assert %Brando.Type.ImageConfig{} = assets.default_image.opts.cfg
    assert %Brando.Type.ImageConfig{upload_path: "images/dynamic"} = assets.dynamic_image.opts.cfg
    assert %Brando.Type.VideoConfig{} = assets.default_video.opts.cfg
    assert %Brando.Type.FileConfig{} = assets.default_file.opts.cfg
  end

  test "deferred configs retain their association module metadata" do
    assets = Map.new(Assets.__assets__(ConfiguredAssets), &{&1.name, &1})

    assert %{cfg: :db, module: Brando.Images.Image} = assets.database_image.opts
    assert %{cfg: :config_target, module: Brando.Files.File} = assets.target_file.opts
  end

  test "asset types generate associations to their media schemas" do
    assert %{related: Brando.Images.Image, on_replace: :update} =
             ConfiguredAssets.__schema__(:association, :default_image)

    assert %{related: Brando.Videos.Video, on_replace: :update} =
             ConfiguredAssets.__schema__(:association, :default_video)

    assert %{related: Brando.Files.File, on_replace: :update} =
             ConfiguredAssets.__schema__(:association, :default_file)
  end

  test "rejects invalid static config fields during Blueprint compilation" do
    assert_raise BlueprintError, ~r/:size_limit expected a positive integer/, fn ->
      compile_blueprint(
        quote do
          assets do
            asset :document, :file, cfg: %{size_limit: 0}
          end
        end
      )
    end

    assert_raise BlueprintError, ~r/:completed_callback expected nil, an arity-2 function/, fn ->
      compile_blueprint(
        quote do
          assets do
            asset :cover, :image, cfg: %{completed_callback: :invalid}
          end
        end
      )
    end

    assert_raise BlueprintError, ~r/:sizes expected a non-empty map/, fn ->
      compile_blueprint(
        quote do
          assets do
            asset :cover, :image, cfg: %{sizes: %{}}
          end
        end
      )
    end

    assert_raise BlueprintError, ~r/unknown file config fields: \[:upload_pat\]/, fn ->
      compile_blueprint(
        quote do
          assets do
            asset :document, :file, cfg: %{upload_pat: "files/typo"}
          end
        end
      )
    end

    assert_raise BlueprintError, ~r/matching config struct/, fn ->
      compile_blueprint(
        quote do
          assets do
            asset :cover, :image, cfg: %Brando.Type.FileConfig{}
          end
        end
      )
    end

    assert_raise BlueprintError, ~r/unknown gallery config fields: \[:upload_pat\]/, fn ->
      compile_blueprint(
        quote do
          assets do
            asset :gallery, :gallery, cfg: %{image: %{upload_path: "images/gallery"}, upload_pat: "images/typo"}
          end
        end
      )
    end
  end

  test "validates deferred config functions when they are materialized" do
    module =
      compile_blueprint(
        quote do
          def invalid_config, do: %{upload_path: ""}

          assets do
            asset :clip, :video, cfg: &__MODULE__.invalid_config/0
          end
        end
      )

    assert_raise BlueprintError, ~r/:upload_path expected a non-empty string/, fn ->
      Assets.__asset__(module, :clip)
    end
  end

  test "runs video callbacks only on the first ready transition" do
    Process.register(self(), __MODULE__)

    config_target = "video:#{inspect(VideoCallbacks)}:clip"
    video = %Brando.Videos.Video{status: :processing, config_target: config_target}
    ready_video = %{video | status: :ready}
    user = %Brando.Users.User{id: 1}

    assert :ok = Brando.Videos.run_completed_callback_on_ready(video, ready_video, user)
    assert_received {:provider_completed, ^ready_video, ^user}

    assert :ok = Brando.Videos.run_completed_callback_on_ready(ready_video, ready_video, user)
    refute_received {:provider_completed, _, _}
  end

  defp compile_blueprint(body) do
    unique = System.unique_integer([:positive])
    module = Module.concat(__MODULE__, "Dynamic#{unique}")
    schema = "Dynamic#{unique}"

    Code.compile_quoted(
      quote do
        defmodule unquote(module) do
          use Brando.Blueprint,
            application: "Brando",
            domain: "AssetConfigTest",
            schema: unquote(schema),
            singular: "dynamic",
            plural: "dynamics",
            gettext_module: Brando.Gettext

          unquote(body)
        end
      end
    )

    module
  end
end
