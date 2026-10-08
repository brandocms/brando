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

  defmodule GalleryCasting do
    use Brando.Blueprint,
      application: "Brando",
      domain: "AssetConfigTest",
      schema: "GalleryCasting",
      singular: "gallery_casting",
      plural: "gallery_castings",
      gettext_module: Brando.Gettext

    assets do
      asset :required_gallery, :gallery,
        cfg: :default,
        required: true,
        required_message: "select a gallery"

      asset :optional_gallery, :gallery, cfg: :default
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

  test "gallery casting enforces required values and preserves optional clearing" do
    changeset =
      GalleryCasting.changeset(
        %GalleryCasting{},
        %{
          "required_gallery" => "",
          "optional_gallery" => ""
        }
      )

    refute changeset.valid?

    assert {"select a gallery", [validation: :required]} =
             changeset.errors[:required_gallery]

    assert Map.has_key?(changeset.changes, :optional_gallery)
    assert is_nil(changeset.changes.optional_gallery)
  end

  test "an ImageMagick flag other than > fails the Blueprint with what to use instead" do
    for {geometry, instead} <- [
          {"400x400^", ~s(use "crop" => true)},
          {"400x300!", ~s(use "crop" => true, with a "ratio")},
          {"50%", "give a width in pixels"},
          {"700<", "sizes only shrink"}
        ] do
      message =
        ~r/:sizes\["hero"\] has the "size" #{Regex.escape(inspect(geometry))} with the ImageMagick flag .*#{Regex.escape(instead)}/

      assert_raise BlueprintError, message, fn ->
        compile_blueprint(
          quote do
            assets do
              asset :cover, :image, cfg: %{sizes: %{"hero" => %{"size" => unquote(geometry)}}}
            end
          end
        )
      end
    end

    # ">" is what every size does, so it stays.
    compile_blueprint(
      quote do
        assets do
          asset :cover, :image, cfg: %{sizes: %{"thumb" => %{"size" => "400x400>", "crop" => true}}}
        end
      end
    )
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

    for strategy <- [:s3, :cloudflare, :vimeo] do
      module =
        compile_blueprint(
          quote do
            assets do
              asset :clip, :video, cfg: %{upload_strategy: unquote(strategy)}
            end
          end
        )

      assert %{upload_strategy: ^strategy} = Assets.__asset__(module, :clip).opts.cfg
    end

    assert_raise BlueprintError, ~r/Mux playback_policies must be \["public"\]/, fn ->
      compile_blueprint(
        quote do
          assets do
            asset :clip, :video, cfg: %{upload_strategy: :mux, meta: %{mux: %{"playback_policies" => ["signed"]}}}
          end
        end
      )
    end

    assert_raise BlueprintError, ~r/Cloudflare signed playback is not supported/, fn ->
      compile_blueprint(
        quote do
          assets do
            asset :clip, :video,
              cfg: %{
                upload_strategy: :cloudflare,
                meta: %{cloudflare: %{"require_signed_urls" => true}}
              }
          end
        end
      )
    end

    assert_raise BlueprintError, ~r/Vimeo password privacy is not supported/, fn ->
      compile_blueprint(
        quote do
          assets do
            asset :clip, :video, cfg: %{upload_strategy: :vimeo, meta: %{vimeo: %{"privacy_view" => "password"}}}
          end
        end
      )
    end

    assert_raise BlueprintError, ~r/Vimeo folder_uri must be an API URI/, fn ->
      compile_blueprint(
        quote do
          assets do
            asset :clip, :video,
              cfg: %{upload_strategy: :vimeo, meta: %{vimeo: %{folder_uri: "https://vimeo.com/manage/folders/1"}}}
          end
        end
      )
    end

    assert_raise BlueprintError, ~r/Cloudflare max_duration_seconds must be a positive integer/, fn ->
      compile_blueprint(
        quote do
          assets do
            asset :clip, :video,
              cfg: %{
                upload_strategy: :cloudflare,
                meta: %{cloudflare: %{"max_duration_seconds" => 0}}
              }
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

  test "checks image sizes and srcsets during Blueprint compilation" do
    assert_raise BlueprintError, ~r/:sizes\["thumb"\] has an unknown key "crp" \(did you mean "crop"\?\)/, fn ->
      compile_blueprint(
        quote do
          assets do
            asset :cover, :image, cfg: %{sizes: %{"thumb" => %{"size" => "400x400", "crp" => true}}}
          end
        end
      )
    end

    assert_raise BlueprintError, ~r/:sizes\["thumb"\] is cropped but its "size" gives one dimension/, fn ->
      compile_blueprint(
        quote do
          assets do
            asset :gallery, :gallery, cfg: %{image: %{sizes: %{"thumb" => %{"size" => "400", "crop" => true}}}}
          end
        end
      )
    end

    assert_raise BlueprintError,
                 ~r/:srcset \[:cropped\] names the size "huge", which is not in :sizes \["large", "small"\]/,
                 fn ->
                   compile_blueprint(
                     quote do
                       assets do
                         asset :cover, :image,
                           cfg: %{
                             sizes: %{"small" => %{"size" => "700"}, "large" => %{"size" => "1400"}},
                             srcset: %{default: [{"small", "700w"}], cropped: [{"huge", "2400w"}]}
                           }
                       end
                     end
                   )
                 end

    assert_raise BlueprintError, ~r/:srcset has an invalid descriptor "700"/, fn ->
      compile_blueprint(
        quote do
          assets do
            asset :cover, :image, cfg: %{srcset: [{"small", "700"}]}
          end
        end
      )
    end

    assert_raise BlueprintError, ~r/:sizes uses the unknown size preset :huge/, fn ->
      compile_blueprint(
        quote do
          assets do
            asset :cover, :image, cfg: %{sizes: :huge}
          end
        end
      )
    end
  end

  test "image sizes accept presets and atom keys, and are stored as string-keyed maps" do
    module =
      compile_blueprint(
        quote do
          assets do
            asset :standard, :image, cfg: %{sizes: :standard}

            asset :extended, :image,
              cfg: %{
                sizes: {:standard, %{hero: %{size: "2400", quality: 80}}},
                srcset: %{default: [{"small", "700w"}, {"hero", "2400w"}]}
              }

            asset :gallery, :gallery, cfg: %{image: %{sizes: {:standard, %{"hero" => %{"size" => "2400"}}}}}
          end
        end
      )

    standard = Brando.Images.Size.preset!(:standard)

    assert Assets.__asset__(module, :standard).opts.cfg.sizes == standard

    extended = Assets.__asset__(module, :extended).opts.cfg
    assert extended.sizes == Map.put(standard, "hero", %{"size" => "2400", "quality" => 80})

    assert %{"hero" => %{"size" => "2400"}, "xlarge" => _} = Assets.__asset__(module, :gallery).opts.cfg.image.sizes
  end

  test "replacing sizes drops an inherited srcset that names sizes no longer there" do
    module =
      compile_blueprint(
        quote do
          assets do
            # The default srcset names small … xlarge.
            asset :logo, :image, cfg: %{sizes: %{"thumb" => %{"size" => "300x300", "crop" => true}}}

            asset :cover, :image, cfg: %{sizes: {:standard, %{"hero" => %{"size" => "2400"}}}}
          end
        end
      )

    assert Assets.__asset__(module, :logo).opts.cfg.srcset == nil
    assert %{default: [_ | _]} = Assets.__asset__(module, :cover).opts.cfg.srcset
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
