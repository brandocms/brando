defmodule Brando.News.PostTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  require Forge
  alias Brando.Post

  setup do
    user = Forge.saved_user(TestRepo)
    Forge.having creator: user do
      post = Forge.saved_post(TestRepo)
    end
    {:ok, %{user: user, post: post}}
  end

  test "meta", %{post: post} do
    assert Post.__name__(:singular) == "post"
    assert Post.__name__(:plural) == "posts"
    assert Post.__repr__(post) == "Post title"
  end

  test "delete", %{post: post} do
    refute Brando.repo.all(Post) == []
    Post.delete(post.id)
    assert Brando.repo.all(Post) == []
  end

  test "encode_data" do
    assert Post.encode_data(%{data: "test"}) == %{data: "test"}
  end
end
