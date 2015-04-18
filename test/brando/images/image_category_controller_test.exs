Code.require_file("router_helper.exs", Path.join([__DIR__, "..", ".."]))

defmodule Brando.ImageCategory.ControllerTest do
  use ExUnit.Case
  use Brando.Integration.TestCase
  use Plug.Test
  use RouterHelper
  alias Brando.ImageCategory
  alias Brando.User
  alias Brando.Type.Image.Config

  @user_params %{"avatar" => nil, "role" => ["2", "4"],
                 "email" => "fanogigyni@gmail.com", "full_name" => "Nita Bond",
                 "password" => "finimeze", "status" => "1",
                 "submit" => "Submit", "username" => "zabuzasixu"}
  @params %{"cfg" => %Config{}, "creator_id" => 1, "name" => "Test Category", "slug" => "test-category"}
  @broken_params %{"cfg" => %Config{}, "creator_id" => 1}

  def create_user do
    {:ok, user} = User.create(@user_params)
    user
  end

  test "new" do
    conn = call_with_user(RouterHelper.TestRouter, :get, "/admin/bilder/kategorier/ny")
    assert conn.status == 200
    assert conn.path_info == ["admin", "bilder", "kategorier", "ny"]
    assert conn.private.phoenix_layout == {Brando.Admin.LayoutView, "admin.html"}
  end

  test "edit" do
    user = create_user
    assert {:ok, category} = ImageCategory.create(@params, user)
    conn = call_with_user(RouterHelper.TestRouter, :get, "/admin/bilder/kategorier/#{category.id}/endre")
    assert conn.status == 200
    assert conn.path_info == ["admin", "bilder", "kategorier", "#{category.id}", "endre"]
    assert conn.private.phoenix_layout == {Brando.Admin.LayoutView, "admin.html"}
    assert conn.resp_body =~ "Endre bildekategori"
    assert conn.resp_body =~ "value=\"test-category\""
    conn = call_with_user(RouterHelper.TestRouter, :get, "/admin/bilder/kategorier/1234/endre")
    assert conn.status == 404
  end

  test "create (post) w/params" do
    user = create_user
    params = Map.put(@params, "creator_id", user.id)
    conn = call_with_custom_user(RouterHelper.TestRouter, :post, "/admin/bilder/kategorier/", %{"imagecategory" => params}, user: user)
    assert conn.status == 302
    assert get_resp_header(conn, "Location") == ["/admin/bilder"]
    assert conn.path_info == ["admin", "bilder", "kategorier"]
    assert conn.private.phoenix_layout == {Brando.Admin.LayoutView, "admin.html"}
    %{phoenix_flash: flash} = conn.private
    assert flash == %{"notice" => "Kategori opprettet."}
  end

  test "create (post) w/erroneus params" do
    conn = call_with_user(RouterHelper.TestRouter, :post, "/admin/bilder/kategorier/", %{"imagecategory" => @broken_params})
    assert conn.status == 200
    assert conn.path_info == ["admin", "bilder", "kategorier"]
    assert conn.private.phoenix_layout == {Brando.Admin.LayoutView, "admin.html"}
    %{phoenix_flash: flash} = conn.private
    assert flash == %{"error" => "Feil i skjema"}
  end

  test "update (post) w/params" do
    user = create_user
    params = Map.put(@params, "creator_id", user.id)
    assert {:ok, category} = ImageCategory.create(params, user)
    conn = call_with_user(RouterHelper.TestRouter, :patch, "/admin/bilder/kategorier/#{category.id}", %{"imagecategory" => params})
    assert conn.status == 302
    assert get_resp_header(conn, "Location") == ["/admin/bilder"]
    assert conn.path_info == ["admin", "bilder", "kategorier", "#{category.id}"]
    assert conn.private.phoenix_layout == {Brando.Admin.LayoutView, "admin.html"}
    %{phoenix_flash: flash} = conn.private
    assert flash == %{"notice" => "Kategori oppdatert."}
  end

  test "config (get)" do
    user = create_user
    assert {:ok, category} = ImageCategory.create(@params, user)
    conn = call_with_user(RouterHelper.TestRouter, :get, "/admin/bilder/kategorier/#{category.id}/konfigurer")
    assert conn.status == 200
    assert conn.path_info == ["admin", "bilder", "kategorier", "#{category.id}", "konfigurer"]
    assert conn.private.phoenix_layout == {Brando.Admin.LayoutView, "admin.html"}
    assert conn.resp_body =~ "Konfigurér bildekategori"
    assert conn.resp_body =~ "imagecategoryconfig[cfg]"
    conn = call_with_user(RouterHelper.TestRouter, :get, "/admin/bilder/kategorier/1234/konfigurer")
    assert conn.status == 404
  end

  test "config (post) w/params" do
    user = create_user
    params = Map.put(@params, "creator_id", user.id)
    assert {:ok, category} = ImageCategory.create(params, user)
    conn = call_with_user(RouterHelper.TestRouter, :patch, "/admin/bilder/kategorier/#{category.id}/konfigurer", %{"imagecategoryconfig" => params})
    assert conn.status == 302
    assert get_resp_header(conn, "Location") == ["/admin/bilder"]
    assert conn.path_info == ["admin", "bilder", "kategorier", "#{category.id}", "konfigurer"]
    assert conn.private.phoenix_layout == {Brando.Admin.LayoutView, "admin.html"}
    %{phoenix_flash: flash} = conn.private
    assert flash == %{"notice" => "Kategori konfigurert."}
  end

  test "delete_confirm" do
    user = create_user
    assert {:ok, category} = ImageCategory.create(@params, user)
    conn = call_with_user(RouterHelper.TestRouter, :get, "/admin/bilder/kategorier/#{category.id}/slett")
    assert conn.status == 200
    assert conn.path_info == ["admin", "bilder", "kategorier", "#{category.id}", "slett"]
    assert conn.resp_body =~ "Slett bildekategori: Test Category"
  end

  test "delete" do
    user = create_user
    assert {:ok, category} = ImageCategory.create(@params, user)
    conn = call_with_user(RouterHelper.TestRouter, :delete, "/admin/bilder/kategorier/#{category.id}")
    assert conn.status == 302
    assert conn.path_info == ["admin", "bilder", "kategorier", "#{category.id}"]
    assert conn.private.phoenix_layout == {Brando.Admin.LayoutView, "admin.html"}
    assert get_resp_header(conn, "Location") == ["/admin/bilder"]
    %{phoenix_flash: flash} = conn.private
    assert flash == %{"notice" => "bildekategori Test Category slettet."}
  end
end