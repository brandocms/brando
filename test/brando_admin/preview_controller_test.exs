defmodule BrandoAdmin.PreviewControllerTest do
  use Brando.ConnCase
  alias Brando.Sites.Preview

  test "shared previews expire even when the purge worker has not run" do
    user = Brando.Factory.insert(:random_user, avatar: nil)

    preview =
      Repo.insert!(%Preview{
        creator_id: user.id,
        preview_key: Ecto.UUID.generate(),
        html: Brando.Utils.term_to_binary("<main>Shared draft</main>"),
        expires_at: DateTime.utc_now() |> DateTime.add(60, :second) |> DateTime.truncate(:second)
      })

    response = Brando.PreviewController.show(build_conn(), %{"preview_key" => preview.preview_key})
    assert response.status == 200
    assert response.resp_body =~ "Shared draft"
    assert {:snooze, seconds} = Brando.Worker.PreviewPurger.perform(%Oban.Job{args: %{"id" => preview.id}})
    assert seconds > 0
    assert Repo.get(Preview, preview.id)
    Repo.update!(Ecto.Changeset.change(preview, expires_at: ~U[2020-01-01 00:00:00Z]))
    Brando.Cache.Query.evict(preview)

    assert {:error, {:preview, :not_found}} =
             Brando.PreviewController.show(build_conn(), %{"preview_key" => preview.preview_key})

    assert :ok = Brando.Worker.PreviewPurger.perform(%Oban.Job{args: %{"id" => preview.id}})
    refute Repo.get(Preview, preview.id)
  end
end
