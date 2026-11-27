# Gives the published "about" page a video block, as an editor adds one: a
# module with a video ref, and a block whose ref shows an autoplaying video
# file. Lazy is the default, so the stored HTML has the source in `data-src`
# only, and video.spec.js checks that the installed frontend plays it. No
# server serves the file: the browser test answers its URL.
alias Brando.Content.Block
alias Brando.Pages.Page
alias Brando.Tenant.Job

user = Brando.Repo.get_by!(Brando.Users.User, email: "installer@example.test")
src = "https://media.smoke.test/clip.webm"

Job.each_active_environment(:live, fn ->
  {:ok, video} =
    %Brando.Videos.Video{}
    |> Brando.Videos.Video.changeset(%{type: :external_file, source_url: src, width: 160, height: 90}, user)
    |> Brando.Repo.insert()

  {:ok, module} =
    Brando.Content.create_module(
      %{
        name: %{"en" => "Video"},
        namespace: %{"en" => "Media"},
        help_text: %{"en" => "A video"},
        class: "video",
        code: "{% ref refs.clip %}",
        refs: [%{name: "clip", uid: Brando.Utils.generate_uid(), data: %{type: "video", data: %{}}}]
      },
      user
    )

  page = Brando.Repo.get_by!(Page, uri: "about", language: :en)

  block =
    %Block{}
    |> Block.recursive_block_changeset(
      %{
        "uid" => Brando.Utils.generate_uid(),
        "type" => "module",
        "module_id" => module.id,
        "creator_id" => user.id,
        "source" => to_string(Page.Blocks),
        "refs" => [
          %{
            "uid" => Brando.Utils.generate_uid(),
            "name" => "clip",
            "video_id" => video.id,
            "data" => %{"type" => "video", "data" => %{"autoplay" => true}}
          }
        ]
      },
      user
    )
    |> Brando.Repo.insert!()

  struct(Page.Blocks, %{entry_id: page.id, block_id: block.id, sequence: 0}) |> Brando.Repo.insert!()
  {:ok, _} = Brando.Content.Blocks.render_entry(Page, page.id)
  %{rendered_blocks: html} = Brando.Repo.get!(Page, page.id)
  true = html =~ ~s(data-preload="#{src}")
end)

IO.puts("A video block on the about page in every live environment")
