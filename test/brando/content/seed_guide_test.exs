defmodule Brando.Content.SeedGuideTest do
  # The seed script in guides/seeding.md, run as the guide shows it: read from
  # the guide, in a directory with the file it uploads, against a site with the
  # user and the module it names. A change that breaks the example fails here.
  use Brando.ConnCase, async: false
  use Brando.Test

  alias Brando.Pages.Page

  @guide Path.expand("../../../guides/seeding.md", __DIR__)
  @external_resource @guide

  setup do
    user = insert_user(email: "admin@example.com")

    {:ok, _module} =
      Brando.Content.create_module(
        Brando.Factory.params_for(:module,
          uid: "image-row",
          name: %{"en" => "Image row"},
          namespace: %{"en" => "Content"},
          help_text: %{"en" => "A picture with a caption"},
          code: ~s(<figure class="image-row">{% ref refs.picture %}{% ref refs.caption %}</figure>),
          refs: [
            Brando.ProposalFixtures.ref("picture", %{type: "picture", data: %{}}),
            Brando.ProposalFixtures.ref("caption", %{type: "text", data: %{text: ""}})
          ],
          vars: []
        ),
        user
      )

    dir = Path.join(System.tmp_dir!(), "brando-seed-guide-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "priv/seeds"))
    File.cp!(Path.expand("../../fixtures/sample.jpg", __DIR__), Path.join(dir, "priv/seeds/lobby.jpg"))
    on_exit(fn -> File.rm_rf(dir) end)

    %{dir: dir}
  end

  test "the guide's seed script creates a page with an image row, and finds it when run again", %{dir: dir} do
    script = example!()

    {page, _binding} = File.cd!(dir, fn -> Code.eval_string(script) end)

    assert %Page{uri: "lobby", language: :en, status: :published} = page
    assert page.rendered_blocks =~ ~s(<figure class="image-row">)
    assert page.rendered_blocks =~ "<img"
    assert page.rendered_blocks =~ "Open from eight."

    {again, _binding} = File.cd!(dir, fn -> Code.eval_string(script) end)
    assert again.id == page.id
    assert Brando.Repo.aggregate(Page, :count) == 1
    assert Brando.Repo.aggregate(Brando.Images.Image, :count) == 1
  end

  # The Elixir fence after the `<!-- seeding-example -->` marker
  defp example! do
    [_before, rest] = @guide |> File.read!() |> String.split("<!-- seeding-example -->\n", parts: 2)
    [_, code] = Regex.run(~r/\A```elixir\n(.*?)\n```/s, rest)
    code
  end
end
