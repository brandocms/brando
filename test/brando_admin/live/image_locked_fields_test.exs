defmodule BrandoAdmin.ImageLockedFieldsTest do
  # The image form's Technical tab is read-only but for superusers. The
  # browser only renders it so: the save takes no value for those fields from
  # anyone else, nor for the sizes processing writes, so a crafted request
  # cannot point an image's path (which the crop editor writes to) elsewhere.
  use Brando.LiveCase

  alias Brando.Images.Image
  alias BrandoAdmin.Components.Form.LockedFields

  @form "#image_form_form"
  @traversal "../../../../../../../../tmp/locked-fields-marker.jpg"

  setup do
    %{image: Factory.insert(:image, path: "images/locked/a.jpg", status: :processed)}
  end

  defp log_in(role) do
    user = Factory.insert(:random_user, role: role, config: %Brando.Users.UserConfig{})
    Phoenix.ConnTest.build_conn() |> log_in_user(user)
  end

  defp save(view, params) do
    view |> form(@form) |> render_submit(%{"image" => params})
    assert_redirect(view, 3_000)
  end

  test "an editor's save keeps the image's path, size and target", %{image: image} do
    {view, _html} = live_form(log_in(:editor), "/admin/assets/images/update/#{image.id}", "image_form")

    save(view, %{
      "path" => @traversal,
      "config_target" => "image:Elsewhere:cover",
      "width" => "1",
      "height" => "1",
      "sizes" => %{"thumb" => @traversal},
      "credits" => %{"en" => "Edited"}
    })

    saved = Repo.get!(Image, image.id)
    assert saved.path == image.path
    assert saved.config_target == image.config_target
    assert {saved.width, saved.height} == {image.width, image.height}
    assert saved.sizes == image.sizes
    # The rest of the form saves as before
    assert saved.credits["en"] == "Edited"
  end

  test "a superuser can still correct the path, inside the media root", %{conn: conn, image: image} do
    {view, _html} = live_form(conn, "/admin/assets/images/update/#{image.id}", "image_form")
    save(view, %{"path" => "images/locked/b.jpg"})

    assert Repo.get!(Image, image.id).path == "images/locked/b.jpg"

    {view, _html} = live_form(conn, "/admin/assets/images/update/#{image.id}", "image_form")
    # Refused by the changeset (and logged as a failed save)
    ExUnit.CaptureLog.capture_log(fn ->
      view |> form(@form) |> render_submit(%{"image" => %{"path" => @traversal}})
    end)

    assert Repo.get!(Image, image.id).path == "images/locked/b.jpg"
  end

  describe "LockedFields.fields/3" do
    test "an image's technical fields for anyone but a superuser, its sizes for everyone" do
      blueprint = Image.__form__(:default)
      editor = %Brando.Users.User{role: :editor}
      superuser = %Brando.Users.User{role: :superuser}

      assert Enum.sort(LockedFields.fields(Image, blueprint, editor)) ==
               Enum.sort([:path, :config_target, :width, :height, :cdn, :sizes, :formats, :status, :config_fingerprint])

      assert Enum.sort(LockedFields.fields(Image, blueprint, superuser)) ==
               Enum.sort([:sizes, :formats, :status, :config_fingerprint])
    end

    test "a superuser fieldset's fields for anyone but a superuser" do
      gallery = Brando.Galleries.Gallery
      blueprint = gallery.__form__(:default)

      assert :config_target in LockedFields.fields(gallery, blueprint, %Brando.Users.User{role: :user})
      refute :config_target in LockedFields.fields(gallery, blueprint, %Brando.Users.User{role: :superuser})
    end
  end
end
