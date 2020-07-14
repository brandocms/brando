# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     <%= application_module %>.Repo.insert!(%SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

post_cfg = %Brando.Type.ImageConfig{allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
    default_size: "xlarge", random_filename: true, size_limit: 10_240_000,
    sizes: %{
      "large" => %{"quality" => 85, "size" => "1400"},
      "medium" => %{"quality" => 85, "size" => "1000"},
      "micro" => %{"crop" => false, "quality" => 10, "size" => "25"},
      "small" => %{"quality" => 85, "size" => "700"},
      "thumb" => %{"crop" => true, "quality" => 85, "size" => "150x150"},
      "xlarge" => %{"quality" => 85, "size" => "1900"}},
    upload_path: "images/site/posts"}

ss_cfg = %Brando.Type.ImageConfig{allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
    default_size: "xlarge", random_filename: true, size_limit: 10_240_000,
    sizes: %{
        "cropxlarge" => %{"crop" => true, "quality" => 80, "size" => "1140x600"},
        "large" => %{"quality" => 80, "size" => "1400"},
        "medium" => %{"quality" => 80, "size" => "900"},
        "micro" => %{"crop" => false, "quality" => 10, "size" => "25"},
        "small" => %{"quality" => 80, "size" => "300"},
        "test" => %{"quality" => 80, "size" => "900"},
        "thumb" => %{"crop" => true, "quality" => 80, "size" => "150x150"},
        "xlarge" => %{"quality" => 80, "size" => "2550"}},
    upload_path: "images/site/slideshows"}

# insert admin user
password = Bcrypt.hash_pwd_salt("admin")
user = %Brando.Users.User{
  name: "Twined Admin",
  email: "admin@twined.net", password: password,
  avatar: nil, role: :superuser, language: "no"}
user = <%= application_module %>.Repo.insert!(user)

post_category = %Brando.ImageCategory{
  creator_id: user.id, name: "post", slug: "post",
  cfg: post_cfg}
post_category = <%= application_module %>.Repo.insert!(post_category)

ss_category = %Brando.ImageCategory{
  cfg: ss_cfg,
  creator_id: user.id,
  name: "Slideshows", slug: "slideshows"}

<%= application_module %>.Repo.insert!(ss_category)

post_series = %Brando.ImageSeries{
  creator_id: user.id, credits: nil,
  cfg: post_cfg,
  image_category_id: post_category.id,
  name: "post", sequence: 0, slug: "post"}

<%= application_module %>.Repo.insert!(post_series)

page = %Brando.Pages.Page{
  creator_id: 1,
  css_classes: nil,
  data: [
    %{
      "data" => %{"text" => "<p>Index text.</p>", "type" => "paragraph"},
      "type" => "text"
    }
  ],
  deleted_at: nil,
  fragments: [],
  html: "<p>Index text.</p>",
  id: 1,
  inserted_at: ~N[2020-04-17 12:05:44],
  key: "index",
  language: "en",
  meta_description: nil,
  meta_image: nil,
  parent_id: nil,
  sequence: 0,
  slug: "index",
  status: :published,
  title: "Index",
  updated_at: ~N[2020-04-17 12:05:44]
}

<%= application_module %>.Repo.insert!(page)
