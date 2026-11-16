defmodule Brando.RuntimeDefaultsTest do
  @moduledoc """
  `default_config` under `Brando.Images`, `Brando.Videos` and `Brando.Files`,
  and `config :brando, :default_language`, are read when they are used, not
  when a Blueprint compiles: changed after Brando is compiled (as
  `config/runtime.exs` does), Brando's own Blueprints and an application's
  follow them.
  """
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import ExUnit.CaptureLog

  alias Brando.Blueprint.Assets
  alias Brando.Type.FileConfig
  alias Brando.Type.ImageConfig
  alias Brando.Type.VideoConfig

  defmodule Declared do
    use Brando.Blueprint,
      application: "Brando",
      domain: "RuntimeDefaultsTest",
      schema: "Declared",
      singular: "declared",
      plural: "declared",
      gettext_module: Brando.Gettext

    data_layer :embedded

    assets do
      asset :default_image, :image, cfg: :default
      asset :map_image, :image, cfg: %{upload_path: "images/declared-map", size_limit: 1_000}
      asset :keyword_image, :image, cfg: [upload_path: "images/declared-keyword", formats: [:webp]]
      asset :default_video, :video, cfg: :default
      asset :map_file, :file, cfg: %{upload_path: "files/declared"}
      asset :default_gallery, :gallery, cfg: :default
    end
  end

  # A srcset of its own and no sizes: its sizes come from default_config.
  defmodule OwnSrcset do
    use Brando.Blueprint,
      application: "Brando",
      domain: "RuntimeDefaultsTest",
      schema: "OwnSrcset",
      singular: "own_srcset",
      plural: "own_srcsets",
      gettext_module: Brando.Gettext

    data_layer :embedded

    assets do
      asset :cover, :image,
        cfg: [upload_path: "images/own-srcset", srcset: %{default: [{"small", "700w"}, {"xlarge", "2100w"}]}]

      asset :slides, :gallery, cfg: [upload_path: "images/own-srcset-slides", srcset: [{"xlarge", "2100w"}]]
      asset :plain, :image, cfg: :default
    end
  end

  # default_config with fewer sizes than the one OwnSrcset compiled against
  @narrowed %{
    sizes: %{"micro" => %{"size" => "25", "quality" => 10}, "small" => %{"size" => "700", "quality" => 70}},
    srcset: %{default: [{"small", "700w"}]}
  }

  @config_modules %{Brando.Images => ImageConfig, Brando.Videos => VideoConfig, Brando.Files => FileConfig}

  # `overrides` over the default_config in effect, as an application's
  # runtime.exs writes a whole one
  defp put_default_config(context, overrides) do
    original = Application.get_env(:brando, context)
    on_exit(fn -> restore(context, original) end)

    base =
      case original && Keyword.get(original, :default_config) do
        nil -> Map.from_struct(@config_modules[context].default_config())
        configured -> Map.new(configured)
      end

    Application.put_env(:brando, context, Keyword.put(original || [], :default_config, Map.merge(base, overrides)))
  end

  defp restore(key, nil), do: Application.delete_env(:brando, key)
  defp restore(key, value), do: Application.put_env(:brando, key, value)

  defp cfg(module, name), do: Assets.__asset__(module, name).opts.cfg

  describe "default_config" do
    test "Brando's own assets and an application's Blueprint read the value configured now" do
      put_default_config(Brando.Images, %{upload_path: "images/runtime", overwrite: true, hidden_folder: "runtime"})

      # Brando's: the user avatar and the identity logo declare their own
      # upload path, and take the rest from `default_config`
      assert %ImageConfig{overwrite: true, hidden_folder: "runtime", upload_path: "images/avatars"} =
               cfg(Brando.Users.User, :avatar)

      assert %ImageConfig{overwrite: true, hidden_folder: "runtime"} = cfg(Brando.Sites.Identity, :logo)

      assert %ImageConfig{overwrite: true, upload_path: "images/runtime"} = cfg(Declared, :default_image)
      assert %ImageConfig{overwrite: true} = cfg(Declared, :map_image)
      assert %{image: %ImageConfig{overwrite: true, upload_path: "images/runtime"}} = cfg(Declared, :default_gallery)

      # Every reader goes through the same resolution
      assert [%{opts: %{cfg: %ImageConfig{overwrite: true}}} | _] = Brando.Users.User.__image_fields__()
      assert {:ok, %ImageConfig{overwrite: true}} = Brando.Images.ConfigResolver.get("image:Brando.Users.User:avatar")

      assert %{cfg: %ImageConfig{overwrite: true}} = Assets.__asset_opts__(Declared, :keyword_image)

      assert Enum.all?(Assets.__assets__(Declared), fn
               %{type: :image, opts: %{cfg: cfg}} -> cfg.overwrite
               _other -> true
             end)
    end

    test "a later change is read too" do
      put_default_config(Brando.Images, %{upload_path: "images/first"})
      assert %ImageConfig{upload_path: "images/first"} = cfg(Declared, :default_image)

      put_default_config(Brando.Images, %{upload_path: "images/second"})
      assert %ImageConfig{upload_path: "images/second"} = cfg(Declared, :default_image)
    end

    test "videos and files read their own default_config" do
      put_default_config(Brando.Videos, %{upload_path: "videos/runtime", size_limit: 1_234})
      put_default_config(Brando.Files, %{upload_path: "files/runtime", size_limit: 4_321})

      assert %VideoConfig{upload_path: "videos/runtime", size_limit: 1_234} = cfg(Declared, :default_video)
      assert %{video: %VideoConfig{upload_path: "videos/runtime"}} = cfg(Declared, :default_gallery)
      assert %FileConfig{upload_path: "files/declared", size_limit: 4_321} = cfg(Declared, :map_file)
    end

    test "a default_config holding an anonymous function works" do
      callback = fn _image, _user -> :ok end
      put_default_config(Brando.Images, %{completed_callback: callback})

      assert %ImageConfig{completed_callback: ^callback} = cfg(Brando.Users.User, :avatar)
      assert %ImageConfig{completed_callback: ^callback} = cfg(Declared, :map_image)
    end

    test "a cfg written as a map or a keyword list overrides default_config key by key" do
      put_default_config(Brando.Images, %{
        upload_path: "images/runtime",
        size_limit: 99,
        formats: [:jpg],
        random_filename: true
      })

      assert %ImageConfig{upload_path: "images/declared-map", size_limit: 1_000, formats: [:jpg], random_filename: true} =
               cfg(Declared, :map_image)

      assert %ImageConfig{
               upload_path: "images/declared-keyword",
               size_limit: 99,
               formats: [:webp],
               random_filename: true
             } = cfg(Declared, :keyword_image)
    end
  end

  describe "a default_config without a size a srcset names" do
    setup do
      previous = Logger.level()
      Logger.configure(level: :warning)
      on_exit(fn -> Logger.configure(level: previous) end)
      put_default_config(Brando.Images, @narrowed)
      :ok
    end

    test "the field is read without the entries naming it, with one warning" do
      log =
        capture_log(fn ->
          assert %ImageConfig{srcset: %{default: [{"small", "700w"}]}} = cfg(OwnSrcset, :cover)
          assert %{image: %ImageConfig{srcset: nil}} = cfg(OwnSrcset, :slides)
          assert %ImageConfig{srcset: %{default: [{"small", "700w"}]}} = cfg(OwnSrcset, :plain)
          assert [_cover, _plain] = OwnSrcset.__image_fields__()
          assert length(Assets.__assets__(OwnSrcset)) == 3
          assert %{cfg: %ImageConfig{}} = Assets.__asset_opts__(OwnSrcset, :cover)

          assert {:ok, %ImageConfig{srcset: %{default: [{"small", "700w"}]}}} =
                   Brando.Images.ConfigResolver.get("image:#{inspect(OwnSrcset)}:cover")
        end)

      assert [_once] = Regex.scan(~r/RuntimeDefaultsTest.OwnSrcset.cover: its srcset names "xlarge"/, log)
      assert [_once] = Regex.scan(~r/RuntimeDefaultsTest.OwnSrcset.slides: its srcset names "xlarge"/, log)
      refute log =~ "OwnSrcset.plain"
    end

    test "a cfg: naming a size missing from its own sizes still fails the Blueprint" do
      assert_raise Brando.Exception.BlueprintError, ~r/names the size "xlarge"/, fn ->
        Brando.Blueprint.AssetConfigNormalizer.normalize_declared_value!(:image, :cover,
          sizes: %{"small" => %{"size" => "700", "quality" => 70}},
          srcset: [{"xlarge", "2100w"}]
        )
      end
    end

    test "every Blueprint can still be walked" do
      capture_log(fn -> assert is_list(Brando.Images.AltText.missing()) end)
      capture_log(fn -> assert is_list(Brando.Images.AltText.entry_alt_targets()) end)
    end

    test "the system check lists the fields" do
      assert [
               {OwnSrcset, :cover, ["xlarge"]},
               {OwnSrcset, :slides, ["xlarge"]}
             ] = Brando.Doctor.Checks.ImageSrcsets.missing_sizes([OwnSrcset, Brando.Users.User])

      assert %Brando.Doctor.Result{status: :warning, items: items, fix: fix} =
               Brando.Doctor.Checks.ImageSrcsets.evaluate([{OwnSrcset, :cover, ["xlarge"]}])

      assert items == ["Brando.RuntimeDefaultsTest.OwnSrcset.cover: xlarge"]
      assert fix =~ "default_config"
    end
  end

  describe "the srcset sizes system check" do
    test "is silent when every srcset names sizes its field has" do
      assert [] = Brando.Doctor.Checks.ImageSrcsets.missing_sizes([OwnSrcset])
      assert %Brando.Doctor.Result{status: :ok} = Brando.Doctor.Checks.ImageSrcsets.run(Brando.Doctor.Context.new([]))
    end
  end

  describe "default_language" do
    setup do
      original = Application.get_env(:brando, :default_language)
      on_exit(fn -> restore(:default_language, original) end)
      Application.put_env(:brando, :default_language, "no")
      :ok
    end

    test "a new user's content language is the default configured now" do
      {:ok, user} =
        Brando.Users.create_user(
          %{
            name: "Runtime Default",
            email: "runtime-default@example.com",
            password: "initial-secret",
            password_confirmation: "initial-secret",
            language: "en",
            role: :editor,
            config: %{show_onboarding: true}
          },
          :system
        )

      assert user.config.content_language == "no"
      assert {:ok, %{config: %{content_language: "no"}}} = Brando.Users.get_user(user.id)
    end

    test "a content language given for a new user is kept" do
      {:ok, user} =
        Brando.Users.create_user(
          %{
            name: "Chosen Language",
            email: "chosen-language@example.com",
            password: "initial-secret",
            password_confirmation: "initial-secret",
            language: "en",
            config: %{content_language: "en"}
          },
          :system
        )

      assert user.config.content_language == "en"
    end

    test "a user signed in with a config that has none gets the default" do
      user = Brando.Factory.insert(:random_user, config: %Brando.Users.UserConfig{})
      token = Brando.Users.generate_user_session_token(user)

      assert %{config: %{content_language: "no"}} = Brando.Users.get_user_by_session_token(token)
    end
  end
end
