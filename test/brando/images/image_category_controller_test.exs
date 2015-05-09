#Code.require_file("router_helper.exs", Path.join([__DIR__, "..", ".."]))

defmodule Brando.ImageCategory.ControllerTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  use Plug.Test
  use RouterHelper
  alias Brando.ImageCategory
  alias Brando.User
  alias Brando.Type.ImageConfig

  @user_params %{"avatar" => nil, "role" => ["2", "4"],
                 "email" => "fanogigyni@gmail.com", "full_name" => "Nita Bond",
                 "password" => "finimeze", "status" => "1",
                 "submit" => "Submit", "username" => "zabuzasixu"}
  @params %{"cfg" => %ImageConfig{}, "name" => "Test Category", "slug" => "test-category"}
  @broken_params %{"cfg" => %ImageConfig{}}

  def create_user do
    {:ok, user} = User.create(@user_params)
    user
  end

  test "new" do
    conn =
      call(:get, "/admin/bilder/kategorier/ny")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Ny bildekategori"
  end

  test "edit" do
    user = create_user
    assert {:ok, category} = ImageCategory.create(@params, user)
    conn =
      call(:get, "/admin/bilder/kategorier/#{category.id}/endre")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Endre bildekategori"

    conn =
      call(:get, "/admin/bilder/kategorier/1234/endre")
      |> with_user
      |> send_request

    assert html_response(conn, 404)
  end

  test "create (post) w/params" do
    user = create_user
    conn =
      call(:post, "/admin/bilder/kategorier/", %{"imagecategory" => Map.put(@params, "creator_id", user.id)})
      |> with_user
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/bilder"
    assert get_flash(conn, :notice) == "Kategori opprettet."
  end

  test "create (post) w/erroneus params" do
    conn =
      call(:post, "/admin/bilder/kategorier/", %{"imagecategory" => @broken_params})
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Ny bildekategori"
    assert get_flash(conn, :error) == "Feil i skjema"
  end

  test "update (post) w/params" do
    user = create_user
    params = Map.put(@params, "creator_id", user.id)

    assert {:ok, category} = ImageCategory.create(params, user)

    conn =
      call(:patch, "/admin/bilder/kategorier/#{category.id}", %{"imagecategory" => params})
      |> with_user
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/bilder"
    assert get_flash(conn, :notice) == "Kategori oppdatert."
  end

  test "config (get)" do
    user = create_user

    assert {:ok, category} = ImageCategory.create(@params, user)

    conn =
      call(:get, "/admin/bilder/kategorier/#{category.id}/konfigurer")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Konfigurér bildekategori"
    assert html_response(conn, 200) =~ "imagecategoryconfig[cfg]"

    conn =
      call(:get, "/admin/bilder/kategorier/1234/konfigurer")
      |> with_user
      |> send_request

    assert html_response(conn, 404)
  end

  test "config (post) w/params" do
    user = create_user
    params = Map.put(@params, "creator_id", user.id)

    assert {:ok, category} = ImageCategory.create(params, user)

    conn =
      call(:patch, "/admin/bilder/kategorier/#{category.id}/konfigurer", %{"imagecategoryconfig" => params})
      |> with_user
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/bilder"
    assert get_flash(conn, :notice) == "Kategori konfigurert."
  end

  test "delete_confirm" do
    user = create_user

    assert {:ok, category} = ImageCategory.create(@params, user)

    conn =
      call(:get, "/admin/bilder/kategorier/#{category.id}/slett")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Slett bildekategori: Test Category"
  end

  test "delete" do
    user = create_user
    assert {:ok, category} = ImageCategory.create(@params, user)
    conn =
      call(:delete, "/admin/bilder/kategorier/#{category.id}")
      |> with_user
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/bilder"
    assert get_flash(conn, :notice) == "bildekategori Test Category slettet."
  end
end