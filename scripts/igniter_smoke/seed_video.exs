# Gives the published "about" page two video blocks, as an editor adds them:
# a module with a video ref, one block whose ref shows an autoplaying video
# file, and one whose ref shows another with a cover, a play button and a
# caption. Lazy is the default, so the stored HTML has the sources in
# `data-src` only, and video.spec.js checks that the installed frontend plays
# them. No server serves the files: the browser test answers their URLs.
alias Brando.Content.Block
alias Brando.Pages.Page
alias Brando.Tenant.Job

user = Brando.Repo.get_by!(Brando.Users.User, email: "installer@example.test")
src = "https://media.smoke.test/clip.webm"
cover_src = "https://media.smoke.test/cover.webm"

Job.each_active_environment(:live, fn ->
  insert_video = fn source_url ->
    %Brando.Videos.Video{}
    |> Brando.Videos.Video.changeset(%{type: :external_file, source_url: source_url, width: 160, height: 90}, user)
    |> Brando.Repo.insert!()
  end

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

  [{src, %{"autoplay" => true}}, {cover_src, %{"play_button" => true, "cover" => "svg", "title" => "<p>A caption</p>"}}]
  |> Enum.with_index()
  |> Enum.each(fn {{source_url, settings}, sequence} ->
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
              "video_id" => insert_video.(source_url).id,
              "data" => %{"type" => "video", "data" => settings}
            }
          ]
        },
        user
      )
      |> Brando.Repo.insert!()

    struct(Page.Blocks, %{entry_id: page.id, block_id: block.id, sequence: sequence}) |> Brando.Repo.insert!()
  end)

  {:ok, _} = Brando.Content.Blocks.render_entry(Page, page.id)
  %{rendered_blocks: html} = Brando.Repo.get!(Page, page.id)
  true = html =~ ~s(data-preload="#{src}")
  true = html =~ ~s(data-preload="#{cover_src}")
  true = html =~ "data-cover"
  true = html =~ "video-play-button"
  true = html =~ "<figcaption>"
end)

IO.puts("Two video blocks on the about page in every live environment")
