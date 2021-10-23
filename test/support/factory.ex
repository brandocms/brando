defmodule Brando.Factory do
  use ExMachina.Ecto, repo: Brando.repo()

  alias Brando.Sites.GlobalSet
  alias Brando.Type.ImageConfig
  alias Brando.Pages.Page
  alias Brando.Pages.Fragment
  alias Brando.Image
  alias Brando.Users.User
  alias Brando.Content
  alias Brando.Content.Module
  alias Brando.Content.Palette
  alias Brando.Images.Image

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

  def global_set_factory do
    %GlobalSet{
      label: "System",
      key: "system",
      language: "en",
      globals: build_list(2, :var_text),
      creator: build(:random_user)
    }
  end

  def var_text_factory do
    %Content.Var.Text{
      type: "text",
      label: "Global label",
      key: sequence(:key, &"key-#{&1}"),
      value: "Hello!"
    }
  end

  def user_factory do
    %User{
      name: "James Williamson",
      email: "james@thestooges.com",
      password: @encrypted_password,
      avatar: %Brando.Images.Image{
        width: 300,
        height: 200,
        credits: nil,
        path: "images/avatars/27i97a.jpeg",
        title: "Title!",
        dominant_color: "#deadb33f",
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
      name: "James Williamson",
      email: sequence(:email, &"james#{&1}@thestooges.com"),
      password: @encrypted_password,
      avatar: %Brando.Images.Image{
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

  def palette_factory do
    %Palette{
      name: "base",
      key: "base",
      namespace: "site",
      instructions: "Instructions"
    }
  end

  def color_factory do
    %Palette.Color{
      name: "Color Name",
      key: "colorName",
      hex_value: "#112233"
    }
  end

  def module_factory do
    %Module{
      name: "test",
      namespace: "posts",
      help_text: "help",
      class: "class",
      code: "code here",
      refs: [],
      vars: [],
      svg: nil,
      wrapper: false
    }
  end

  def page_factory do
    %Page{
      uri: sequence(:uri, &"test#{&1}"),
      language: "en",
      status: :published,
      title: "Title",
      template: "default.html",
      data: [],
      creator: build(:random_user)
    }
  end

  def fragment_factory do
    %Fragment{
      parent_key: "index",
      key: "header",
      language: "en",
      data: [],
      html: "fragment content!",
      creator: build(:random_user)
    }
  end

  def image_factory do
    %Image{
      creator_id: nil,
      width: 300,
      height: 292,
      credits: "Credits",
      path: "image/1.jpg",
      formats: [:jpg],
      sizes: %{
        "large" => "image/large/1.jpg",
        "medium" => "image/medium/1.jpg",
        "small" => "image/small/1.jpg",
        "thumb" => "image/thumb/1.jpg",
        "xlarge" => "image/xlarge/1.jpg"
      },
      title: "Title one",
      config_target: "default"
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
