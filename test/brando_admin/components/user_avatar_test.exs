defmodule BrandoAdmin.Components.UserAvatarTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias BrandoAdmin.Components.Content

  test "a user without a photo gets the first letter of their name" do
    html = render_component(&Content.user_avatar/1, %{user: %{name: "kjersti Lund", avatar: nil}})

    assert html =~ ~s(<span class="user-initial">k</span>)
    refute html =~ "img-placeholder"
  end

  test "a nameless user still gets a letter" do
    html = render_component(&Content.user_avatar/1, %{user: %{name: nil, avatar: nil}})

    assert html =~ ~s(<span class="user-initial">?</span>)
  end
end
