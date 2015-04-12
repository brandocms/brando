defmodule Brando.HTML.InspectTest do
  use ExUnit.Case
  use Brando.Integration.TestCase
  import Brando.HTML.Inspect
  alias Brando.Users.Model.User
  alias Brando.News.Model.Post

  @user_params %{"avatar" => nil, "role" => ["2", "4"],
            "email" => "fanogigyni@gmail.com", "full_name" => "Nita Bond",
            "password" => "finimeze", "status" => "1",
            "submit" => "Submit", "username" => "zabuzasixu"}

  @image_map %Brando.Type.Image{credits: nil, optimized: false, path: "images/avatars/27i97a.jpeg", title: nil,
                                sizes: %{thumb: "images/avatars/thumb/27i97a.jpeg", medium: "images/avatars/medium/27i97a.jpeg"}}

  @post_params %{"avatar" => @image_map, "creator_id" => 1,
                 "data" => "[{\"type\":\"text\",\"data\":{\"text\":\"zcxvxcv\"}}]",
                 "featured" => true, "header" => "Header",
                 "html" => "<h1>Header</h1><p>Asdf\nAsdf\nAsdf</p>\n",
                 "language" => "no", "lead" => "Asdf",
                 "meta_description" => nil, "meta_keywords" => nil,
                 "publish_at" => nil, "published" => false,
                 "slug" => "header", "status" => :published}

  @association_has %Ecto.Association.Has{assoc: Brando.Images.Model.Image, assoc_key: :image_series_id, cardinality: :many, field: :images, owner: Brando.Images.Model.ImageSeries, owner_key: :id, queryable: Brando.Images.Model.Image}
  @association_val [%Brando.Images.Model.Image{__meta__: %Ecto.Schema.Metadata{source: "images", state: :loaded}, creator_id: 1, id: 74, image: %Brando.Type.Image{credits: nil, optimized: false, path: "images/default/2ambet.jpg", sizes: %{large: "images/default/large/2ambet.jpg", medium: "images/default/medium/2ambet.jpg", small: "images/default/small/2ambet.jpg", thumb: "images/default/thumb/2ambet.jpg", xlarge: "images/default/xlarge/2ambet.jpg"}, title: nil}, image_series_id: 2, inserted_at: %Ecto.DateTime{day: 3, hour: 14, min: 18, month: 4, sec: 32, usec: 0, year: 2015}, order: 0, updated_at: %Ecto.DateTime{day: 3, hour: 14, min: 18, month: 4, sec: 32, usec: 0, year: 2015}}, %Brando.Images.Model.Image{__meta__: %Ecto.Schema.Metadata{source: "images", state: :loaded}, creator_id: 1, id: 67, image: %Brando.Type.Image{credits: nil, optimized: false, path: "images/default/e9anl.jpg", sizes: %{large: "images/default/large/e9anl.jpg", medium: "images/default/medium/e9anl.jpg", small: "images/default/small/e9anl.jpg", thumb: "images/default/thumb/e9anl.jpg", xlarge: "images/default/xlarge/e9anl.jpg"}, title: nil}, image_series_id: 2, inserted_at: %Ecto.DateTime{day: 3, hour: 14, min: 14, month: 4, sec: 58, usec: 0, year: 2015}, order: 1, updated_at: %Ecto.DateTime{day: 3, hour: 14, min: 14, month: 4, sec: 58, usec: 0, year: 2015}}]

  test "model/1" do
    assert {:ok, user} = User.create(@user_params)
    {:safe, ret} = model(user)
    assert ret =~ "zabuzasixu"
    assert ret =~ "Nita Bond"

    assert {:ok, post} = Post.create(@post_params, user)
    post = post |> Brando.get_repo.preload(:creator)
    {:safe, ret} = model(post)
    assert ret =~ "<i class=\"fa fa-times text-danger\">"
    assert ret =~ "Nita Bond"
    assert ret =~ "<p>zcxvxcv</p>"
  end

  test "inspect_field/3" do
    assert inspect_field("name", Brando.Type.Image.Config, "value") ==
      ~s(<em>Konfigurasjonsdata</em>)
    assert inspect_field("name", Brando.Type.Image, @image_map) =~
      "/media/images/avatars/thumb/27i97a.jpeg"
    assert inspect_field(:password, :string, "passord") =~ "sensurert"
    assert inspect_field("name", :string, "") =~ "Ingen verdi"
  end

  test "inspect_assoc/3" do
    assert inspect_assoc("name", %Ecto.Association.Has{}, %Ecto.Association.NotLoaded{}) =~
      "Assosiasjonene er ikke hentet."
    assert inspect_assoc("name", %Ecto.Association.Has{}, []) =~
      "Ingen assosiasjoner."
    assert inspect_assoc("name", @association_has, @association_val) =~
      "74 | images/default/2ambet.jpg"
  end

  test "model_repr/1" do
    assert {:ok, user} = User.create(@user_params)
    assert model_repr(user) == "Nita Bond (zabuzasixu)"
  end

  test "model_name/2" do
    assert {:ok, user} = User.create(@user_params)
    assert model_name(user, :singular) == "bruker"
    assert model_name(user, :plural) == "brukere"
  end
end