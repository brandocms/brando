defmodule Brando.Content.Proposals.ImageReplacementConfigTest do
  # The file a replace_image_file brings must be one OLD's image config
  # takes. Synchronous: the image config is application env, which
  # `put_test_env/2` changes for every test running at the time.
  use Brando.ConnCase, async: false

  alias Brando.Content.Proposals
  alias Brando.Content.Proposals.ReplaceImageFile

  setup do
    Brando.ProposalFixtures.context()
  end

  defp image!(name, dimensions, opts \\ []), do: Brando.ImageFileFixtures.file_image(name, dimensions, opts)
  defp replace(old, new), do: %ReplaceImageFile{asset: {:image, old.id}, with: {:image, new.id}}
  defp codes(proposal), do: Enum.map(proposal.problems, & &1.code)

  describe "refused when the proposal is prepared" do
    test "an SVG for a raster image, and a raster image for an SVG", c do
      images_env = Application.get_env(:brando, Brando.Images, [])

      put_test_env(
        Brando.Images,
        Keyword.update!(
          images_env,
          :default_config,
          &Map.update!(&1, :allowed_mimetypes, fn t -> t ++ ["image/svg+xml"] end)
        )
      )

      raster = image!("photo", {800, 600})
      svg = image!("logo", {80, 60}, ext: "svg")
      other_svg = image!("logo-new", {80, 60}, ext: "svg")

      assert {:ok, proposal} = Proposals.propose([replace(raster, svg)], c.user)
      assert codes(proposal) == [:wrong_media_type]
      assert {:ok, proposal} = Proposals.propose([replace(svg, raster)], c.user)
      assert codes(proposal) == [:wrong_media_type]
      assert {:ok, %{problems: []}} = Proposals.propose([replace(svg, other_svg)], c.user)
    end

    test "a file OLD's field does not take, by type or size, or the same file", c do
      images_env = Application.get_env(:brando, Brando.Images, [])
      old = image!("a", {800, 600})
      png = image!("b", {800, 600}, ext: "png")

      put_test_env(
        Brando.Images,
        Keyword.update!(images_env, :default_config, &Map.put(&1, :allowed_mimetypes, ["image/jpeg"]))
      )

      assert {:ok, proposal} = Proposals.propose([replace(old, png)], c.user)
      assert codes(proposal) == [:wrong_media_type]
      assert hd(proposal.problems).message =~ "PNG"

      put_test_env(Brando.Images, Keyword.update!(images_env, :default_config, &Map.put(&1, :size_limit, 100)))
      new = image!("c", {800, 600})
      assert {:ok, proposal} = Proposals.propose([replace(old, new)], c.user)
      assert codes(proposal) == [:too_large]

      put_test_env(Brando.Images, images_env)
      copy = image!("d", {800, 600}, content_hash: old.content_hash)
      assert {:ok, proposal} = Proposals.propose([replace(old, copy)], c.user)
      assert codes(proposal) == [:same_file]
    end
  end

  describe "between preparing and approving" do
  end

  test "an image whose config delivers through another CDN", c do
    # OLD's config has no CDN; NEW's, a field's own, delivers through one
    old = image!("a", {800, 600})
    new = image!("b", {1600, 1200}, config_target: "image:Brando.BlueprintTest.Project:cover_cdn")
    assert {:ok, proposal} = Proposals.propose([replace(old, new)], c.user)
    assert codes(proposal) == [:different_delivery]

    # Two images of the same config
    assert {:ok, %{problems: []}} = Proposals.propose([replace(old, image!("c", {1600, 1200}))], c.user)
  end

  describe "a NEW only the CDN has" do
    import Mox

    setup :verify_on_exit!

    test "is read once, when the proposal is prepared, not at approval or apply", c do
      images_env = Application.get_env(:brando, Brando.Images, [])

      cdn = %{
        enabled: true,
        bucket: "testbucket",
        media_url: "https://testbucket.example.com",
        s3: %Brando.CDN.S3Config{access_key_id: "KEY", secret_access_key: "SECRET", region: "ams3"},
        keep_local_copy: false
      }

      put_test_env(Brando.Images, Keyword.update!(images_env, :default_config, &Map.put(&1, :cdn, cdn)))

      old = image!("a", {800, 600})
      new = image!("b", {1600, 1200})
      bytes = File.read!(Brando.Images.Utils.media_path(new.path))
      File.rm!(Brando.Images.Utils.media_path(new.path))
      object_key = Path.join("media", new.path)

      expect(Brando.CDN.Client.Mock, :get_object, 1, fn "testbucket", ^object_key, _ ->
        {:ok, %{status_code: 200, body: bytes}}
      end)

      {:ok, proposal} = Proposals.propose([replace(old, new)], c.user)
      assert proposal.problems == []

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _} = Proposals.approve(proposal.id, proposal.version, c.user)
        assert {:ok, _} = Proposals.apply(proposal.id, proposal.version, c.user)
      end)

      assert Brando.Repo.get!(Brando.Images.Image, old.id).path == new.path
    end
  end
end
