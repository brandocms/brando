defmodule Brando.Factory do
  use ExMachina.Ecto, repo: Brando.repo

  alias Brando.Type.ImageConfig
  alias Brando.{
    Image, ImageCategory, ImageSeries, User
  }

  @sizes %{
    "small" =>  %{"size" => "300", "quality" => 100},
    "thumb" =>  %{"size" => "150x150", "quality" => 100, "crop" => true}
  }

  def factory(:user) do
    %User{
      full_name: "James Williamson",
      email: "james@thestooges.com",
      password: "$2b$12$VD9opg289oNQAHii8VVpoOIOe.y4kx7.lGb9SYRwscByP.tRtJTsa",
      username: "jamesw",
      avatar: %Brando.Type.Image{
        credits: nil,
        optimized: false,
        path: "images/avatars/27i97a.jpeg",
        title: nil,
        sizes: %{
          "thumb" => "images/avatars/thumb/27i97a.jpeg",
          "medium" => "images/avatars/medium/27i97a.jpeg"
        }
      },
      role: [:admin, :superuser],
      language: "en"
    }
  end

  def factory(:user_params) do
    %{
      "full_name" => "James Williamson",
      "email" => "james@thestooges.com",
      "password" => "$2b$12$VD9opg289oNQAHii8VVpoOIOe.y4kx7.lGb9SYRwscByP.tRtJTsa",
      "username" => "jamesw",
      "avatar" => nil,
      "role" => [:admin, :superuser],
      "language" => "en"
    }
  end

  def factory(:image_series) do
    %ImageSeries{
      name: "Series name",
      slug: "series-name",
      cfg: %ImageConfig{sizes: @sizes, upload_path: "portfolio/test-category/test-series"},
      sequence: 0,
      image_category: build(:image_category),
      creator: build(:user),
    }
  end

  def factory(:image_series_params) do
    %{
      "name" => "Series name",
      "slug" => "series-name",
      "cfg" => %ImageConfig{sizes: @sizes},
      "sequence" => 0,
      "image_category" => build(:image_category),
      "creator" => build(:user),
    }
  end

  def factory(:image_category) do
    %ImageCategory{
      cfg: %ImageConfig{sizes: @sizes, upload_path: "portfolio/test-category"},
      name: "Test Category",
      slug: "test-category",
      creator: build(:user)
    }
  end

  def factory(:image_category_params) do
    %{
      "cfg" => %ImageConfig{sizes: @sizes},
      "name" => "Test Category 2",
      "slug" => "test-category-2"
    }
  end

  def factory(:image_type) do
    %Brando.Type.Image{
      credits: nil,
      optimized: false,
      path: "images/default/sample.png",
      sizes: %{
        "large" => "images/default/large/sample.png",
        "medium" => "images/default/medium/sample.png",
        "micro" => "images/default/micro/sample.png",
        "small" => "images/default/small/sample.png",
        "thumb" => "images/default/thumb/sample.png",
        "xlarge" => "images/default/xlarge/sample.png"},
      title: nil
    }
  end

  def factory(:image_cfg_params) do
    %{
      allowed_mimetypes: ["image/jpeg", "image/png"],
      default_size: :medium,
      upload_path: Path.join("images", "default"),
      random_filename: false,
      size_limit: 10_240_000,
      sizes: %{
        "small" =>  %{"size" => "300", "quality" => 100},
        "medium" => %{"size" => "500", "quality" => 100},
        "large" =>  %{"size" => "700", "quality" => 100},
        "xlarge" => %{"size" => "900", "quality" => 100},
        "thumb" =>  %{"size" => "150x150", "quality" => 100, "crop" => true},
        "micro" =>  %{"size" => "25x25", "quality" => 100, "crop" => true}
      }
    }
  end

  def factory(:plug_upload) do
    %Plug.Upload{
      content_type: "image/png",
      filename: "sample.png",
      path: "#{Path.expand("../", __DIR__)}/fixtures/sample.png"
    }
  end

  def factory(:plug_upload_2) do
    %Plug.Upload{
      content_type: "image/png",
      filename: "sample2.png",
      path: "#{Path.expand("../", __DIR__)}/fixtures/sample2.png"
    }
  end

  def factory(:plug_upload_jpeg) do
    %Plug.Upload{
      content_type: "image/jpeg",
      filename: "sample.jpg",
      path: "#{Path.expand("../", __DIR__)}/fixtures/sample.jpg"
    }
  end
end
