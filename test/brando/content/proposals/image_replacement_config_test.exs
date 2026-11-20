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
end
