defmodule Brando.Factory do
  use ExMachina.Ecto, repo: Brando.repo()

  alias Brando.Sites.Global
  alias Brando.Sites.GlobalCategory
  alias Brando.Type.ImageConfig
  alias Brando.Pages.Page
  alias Brando.Pages.PageFragment
  alias Brando.Image
  alias Brando.ImageCategory
  alias Brando.ImageSeries
  alias Brando.Users.User
  alias Brando.Villain.Template

  @sizes %{
    "micro" => %{"size" => "25", "quality" => 1},
    "mobile" => %{"size" => "300", "quality" => 1},
    "small" => %{"size" => "300", "quality" => 1},
    "medium" => %{
      "portrait" => %{"size" => "300", "quality" => 1},
      "landscape" => %{"size" => "250", "quality" => 1}
    },
    "thumb" => %{"size" => "150x150", "quality" => 1, "crop" => true}
  }

  @encrypted_password Bcrypt.hash_pwd_salt("admin")

  def global_category_factory do
    %GlobalCategory{
      label: "System",
      key: "system",
      globals: [build_list(2, :global)]
    }
  end

  def global_factory do
    %Global{
      type: "string",
      label: "Global label",
      key: sequence(:key, &"key-#{&1}"),
      data: %{
        "type" => "string",
        "value" => "Hello!"
      }
    }
  end

  def user_factory do
    %User{
      full_name: "James Williamson",
      email: "james@thestooges.com",
      password: @encrypted_password,
      avatar: %Brando.Type.Image{
        width: 300,
        height: 200,
        credits: nil,
        path: "images/avatars/27i97a.jpeg",
        title: "Title!",
        sizes: %{
          "micro" => "images/avatars/micro/27i97a.jpeg",
          "thumb" => "images/avatars/thumb/27i97a.jpeg",
          "small" => "images/avatars/small/27i97a.jpeg",
          "medium" => "images/avatars/medium/27i97a.jpeg",
          "large" => "images/avatars/large/27i97a.jpeg",
          "mobile" => "images/avatars/mobile/27i97a.jpeg"
        }
      },
      role: :superuser,
      language: "en"
    }
  end

  def random_user_factory do
    %User{
      full_name: "James Williamson",
      email: sequence(:email, &"james#{&1}@thestooges.com"),
      password: @encrypted_password,
      avatar: %Brando.Type.Image{
        width: 300,
        height: 200,
        credits: nil,
        path: "images/avatars/27i97a.jpeg",
        title: "Title!",
        sizes: %{
          "micro" => "images/avatars/micro/27i97a.jpeg",
          "thumb" => "images/avatars/thumb/27i97a.jpeg",
          "small" => "images/avatars/small/27i97a.jpeg",
          "medium" => "images/avatars/medium/27i97a.jpeg",
          "large" => "images/avatars/large/27i97a.jpeg",
          "mobile" => "images/avatars/mobile/27i97a.jpeg"
        }
      },
      role: :superuser,
      language: "en"
    }
  end

  def template_factory do
    %Template{
      name: "test",
      namespace: "posts",
      help_text: "help",
      class: "class",
      code: "code here",
      refs: [],
      vars: %{},
      svg: nil,
      multi: false,
      wrapper: nil
    }
  end

  def page_factory do
    %Page{
      key: sequence(:key, &"test#{&1}"),
      language: "en",
      status: :published,
      title: "Title",
      slug: "title",
      template: "default.html",
      data: [],
      creator: build(:random_user)
    }
  end

  def page_fragment_factory do
    %PageFragment{
      parent_key: "index",
      key: "header",
      language: "en",
      data: [],
      html: "fragment content!",
      creator: build(:random_user)
    }
  end

  def image_series_factory do
    %ImageSeries{
      name: "Series name",
      slug: "series-name",
      cfg: %ImageConfig{sizes: @sizes, upload_path: "portfolio/test-category/test-series"},
      sequence: 0,
      image_category: build(:image_category),
      creator: build(:random_user)
    }
  end

  def image_factory do
    %Image{
      image_series_id: nil,
      creator_id: nil,
      image: %Brando.Type.Image{
        width: 300,
        height: 292,
        credits: "Credits",
        path: "image/1.jpg",
        sizes: %{
          "large" => "image/large/1.jpg",
          "medium" => "image/medium/1.jpg",
          "small" => "image/small/1.jpg",
          "thumb" => "image/thumb/1.jpg",
          "xlarge" => "image/xlarge/1.jpg"
        },
        title: "Title one"
      }
    }
  end

  def image_category_factory do
    %ImageCategory{
      cfg: %ImageConfig{sizes: @sizes, upload_path: "portfolio/test-category"},
      name: "Test Category",
      slug: "test-category",
      creator: build(:random_user)
    }
  end

  def image_type_factory do
    %Brando.Type.Image{
      credits: nil,
      path: "images/default/sample.png",
      sizes: %{
        "large" => "images/default/large/sample.png",
        "medium" => "images/default/medium/sample.png",
        "micro" => "images/default/micro/sample.png",
        "small" => "images/default/small/sample.png",
        "thumb" => "images/default/thumb/sample.png",
        "xlarge" => "images/default/xlarge/sample.png"
      },
      title: nil
    }
  end

  def image_cfg_factory do
    %Brando.Type.ImageConfig{
      allowed_mimetypes: ["image/jpeg", "image/png"],
      default_size: "medium",
      upload_path: Path.join("images", "default"),
      random_filename: false,
      size_limit: 10_240_000,
      sizes: %{
        "small" => %{"size" => "300", "quality" => 100},
        "medium" => %{
          "portrait" => %{"size" => "300", "quality" => 1},
          "landscape" => %{"size" => "250", "quality" => 1}
        },
        "large" => %{"size" => "700", "quality" => 100},
        "xlarge" => %{"size" => "900", "quality" => 100},
        "thumb" => %{"size" => "150x150", "quality" => 100, "crop" => true},
        "micro" => %{"size" => "25", "quality" => 100}
      }
    }
  end

  def plug_upload_factory do
    %Plug.Upload{
      content_type: "image/png",
      filename: "sample.png",
      path: "#{Path.expand("../", __DIR__)}/fixtures/sample.png"
    }
  end

  def plug_upload_2_factory do
    %Plug.Upload{
      content_type: "image/png",
      filename: "sample2.png",
      path: "#{Path.expand("../", __DIR__)}/fixtures/sample2.png"
    }
  end

  def plug_upload_jpeg_factory do
    %Plug.Upload{
      content_type: "image/jpeg",
      filename: "sample.jpg",
      path: "#{Path.expand("../", __DIR__)}/fixtures/sample.jpg"
    }
  end
end
