# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     <%= application_module %>.Repo.insert!(%SomeModel{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

# insert admin user
password = Brando.User.gen_password("admin")
user = %Brando.User{
  username: "admin", full_name: "Twined Admin",
  email: "admin@twined.net", password: password,
  avatar: nil, role: 7, language: "no"}
user = <%= application_module %>.Repo.insert!(user)

post_category = %Brando.ImageCategory{
  creator_id: user.id, name: "post", slug: "post",
  cfg: %Brando.Type.ImageConfig{allowed_mimetypes: ["image/jpeg", "image/png"],
    default_size: "medium", random_filename: true, size_limit: 10240000,
    sizes: %{"large" => %{"quality" => 100, "size" => "700"},
      "medium" => %{"quality" => 100, "size" => "500"},
      "micro" => %{"crop" => true, "quality" => 100, "size" => "25x25"},
      "small" => %{"quality" => 100, "size" => "300"},
      "thumb" => %{"crop" => true, "quality" => 100, "size" => "150x150"},
      "xlarge" => %{"quality" => 100, "size" => "900"}},
    upload_path: "images/posts"}}
post_category = <%= application_module %>.Repo.insert!(post_category)

page_category = %Brando.ImageCategory{
  creator_id: user.id, name: "page", slug: "page",
  cfg: %Brando.Type.ImageConfig{allowed_mimetypes: ["image/jpeg", "image/png"],
    default_size: "medium", random_filename: true, size_limit: 10240000,
    sizes: %{"large" => %{"quality" => 100, "size" => "700"},
      "medium" => %{"quality" => 100, "size" => "500"},
      "micro" => %{"crop" => true, "quality" => 100, "size" => "25x25"},
      "small" => %{"quality" => 100, "size" => "300"},
      "thumb" => %{"crop" => true, "quality" => 100, "size" => "150x150"},
      "xlarge" => %{"quality" => 100, "size" => "900"}},
    upload_path: "images/pages"}}
page_category = <%= application_module %>.Repo.insert!(page_category)

ss_category = %Brando.ImageCategory{
  cfg: %Brando.Type.ImageConfig{allowed_mimetypes: ["image/jpeg", "image/png"],
    default_size: "medium", random_filename: true, size_limit: 10240000,
    sizes: %{"cropxlarge" => %{"crop" => true, "quality" => 100,
        "size" => "1140x600"}, "large" => %{"quality" => 100, "size" => "700"},
        "medium" => %{"quality" => 100, "size" => "500"},
        "micro" => %{"crop" => true, "quality" => 100, "size" => "25x25"},
        "small" => %{"quality" => 100, "size" => "300"},
        "test" => %{"quality" => 100, "size" => "900"},
        "thumb" => %{"crop" => true, "quality" => 100, "size" => "150x150"},
        "xlarge" => %{"quality" => 100, "size" => "2550"}},
    upload_path: "images/slideshows"},
  creator_id: user.id,
  name: "Slideshows", slug: "slideshows"}

<%= application_module %>.Repo.insert!(ss_category)

post_series = %Brando.ImageSeries{
  creator_id: user.id, credits: nil,
  image_category_id: post_category.id,
  name: "post", sequence: 0, slug: "post"}

<%= application_module %>.Repo.insert!(post_series)

page_series = %Brando.ImageSeries{
  creator_id: user.id, credits: nil,
  image_category_id: page_category.id,
  name: "page", sequence: 0, slug: "page"}

<%= application_module %>.Repo.insert!(page_series)
