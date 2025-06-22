defmodule Brando.Factory do
  @moduledoc false
  use ExMachina.Ecto, repo: Brando.Repo.repo()

  alias Brando.Content
  alias Brando.Content.Module
  alias Brando.Content.Palette
  alias Brando.Image
  alias Brando.Images.Image
  alias Brando.Pages.Fragment
  alias Brando.Pages.Page
  alias Brando.Sites.GlobalSet
  alias Brando.Users.User

  @encrypted_password Bcrypt.hash_pwd_salt("admin")

  def global_set_factory do
    %GlobalSet{
      label: "System",
      key: "system",
      language: "en",
      vars: build_list(2, :var_text),
      creator: build(:random_user)
    }
  end

  def var_text_factory do
    %Content.Var{
      type: :text,
      label: "Global label",
      key: sequence(:key, &"key-#{&1}"),
      value: "Hello!",
      creator: build(:random_user)
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
        },
        config_target: "image:Brando.Users.User:avatar"
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
      multi: false
    }
  end

  def ref_factory do
    %Brando.Content.Ref{
      name: sequence(:ref_name, &"test_ref_#{&1}"),
      description: "A test ref",
      uid: Brando.Utils.generate_uid(),
      data: %Brando.Villain.Blocks.TextBlock{
        type: "text",
        data: %Brando.Villain.Blocks.TextBlock.Data{text: "Hello"}
      },
      sequence: 0
    }
  end

  def picture_ref_factory do
    image = build(:image)
    
    %Brando.Content.Ref{
      name: sequence(:ref_name, &"picture_ref_#{&1}"),
      description: "A picture ref",
      uid: Brando.Utils.generate_uid(),
      data: %Brando.Villain.Blocks.PictureBlock{
        type: "picture",
        data: %Brando.Villain.Blocks.PictureBlock.Data{title: "Override title"}
      },
      image: image,
      sequence: 0
    }
  end

  def video_ref_factory do
    video = build(:video)
    
    %Brando.Content.Ref{
      name: sequence(:ref_name, &"video_ref_#{&1}"),
      description: "A video ref", 
      uid: Brando.Utils.generate_uid(),
      data: %Brando.Villain.Blocks.VideoBlock{
        type: "video",
        data: %Brando.Villain.Blocks.VideoBlock.Data{title: "Override title"}
      },
      video: video,
      sequence: 0
    }
  end

  def gallery_factory do
    %Brando.Galleries.Gallery{}
  end

  def video_factory do
    %Brando.Videos.Video{
      source_url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
      type: :youtube,
      remote_id: "dQw4w9WgXcQ",
      width: 1920,
      height: 1080
    }
  end

  def gallery_ref_factory do
    gallery = build(:gallery)
    
    %Brando.Content.Ref{
      name: sequence(:ref_name, &"gallery_ref_#{&1}"),
      description: "A gallery ref",
      uid: Brando.Utils.generate_uid(),
      data: %Brando.Villain.Blocks.GalleryBlock{
        type: "gallery", 
        data: %Brando.Villain.Blocks.GalleryBlock.Data{}
      },
      gallery: gallery,
      sequence: 0
    }
  end

  def module_with_refs_factory do
    module = build(:module)
    refs = [
      build(:ref, module: module),
      build(:picture_ref, module: module)
    ]
    
    %{module | refs: refs}
  end

  def page_factory do
    %Page{
      uri: sequence(:uri, &"test#{&1}"),
      language: :en,
      status: :published,
      title: "Title",
      template: "default.html",
      creator: build(:random_user)
    }
  end

  def fragment_factory do
    %Fragment{
      parent_key: "index",
      key: "header",
      status: :published,
      language: :en,
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
