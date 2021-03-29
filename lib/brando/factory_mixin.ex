defmodule Brando.FactoryMixin do
  @moduledoc """
  Factory entries for Brando.

  ## Usage

  In your `factory.ex`

      use Brando.FactoryMixin

  """
  defmacro __using__(_) do
    quote do
      alias Brando.ImageCategory
      alias Brando.ImageSeries
      alias Brando.Pages.Page
      alias Brando.Pages.Fragment
      alias Brando.Villain.Module
      alias Brando.Type.ImageConfig
      alias Brando.Users.User

      @sizes %{
        "small" => %{"size" => "300", "quality" => 1},
        "medium" => %{
          "portrait" => %{"size" => "300", "quality" => 1},
          "landscape" => %{"size" => "250", "quality" => 1}
        },
        "thumb" => %{"size" => "150x150", "quality" => 1, "crop" => true}
      }

      def user_factory do
        %User{
          name: "James Williamson",
          email: "james@thestooges.com",
          password: Bcrypt.hash_pwd_salt("admin"),
          avatar: nil,
          role: :superuser,
          language: "en"
        }
      end

      def page_factory do
        %Page{
          uri: "a-key",
          language: "no",
          title: "Page Title",
          html: nil,
          data: nil,
          properties: [],
          status: :published,
          creator: build(:user),
          parent_id: nil
        }
      end

      def fragment_factory do
        %Fragment{
          parent_key: "parent",
          key: "a-key",
          language: "no",
          html: nil,
          data: nil,
          creator: build(:user)
        }
      end

      def module_factory do
        %Module{
          class: "header middle",
          code:
            "<article data-v=\"text center\" data-moonwalk-section>\n  <div class=\"inner\" data-moonwalk>\n    <div class=\"text\">\n      %{H2}\n    </div>\n  </div>\n</article>",
          deleted_at: nil,
          help_text: "Help Text",
          multi: false,
          name: "Heading",
          namespace: "general",
          refs: [
            %{
              "data" => %{
                "data" => %{
                  "class" => nil,
                  "id" => nil,
                  "level" => 2,
                  "text" => "Heading here"
                },
                "type" => "header"
              },
              "description" => "A heading",
              "name" => "H2"
            }
          ],
          vars: %{},
          wrapper: nil
        }
      end

      def image_series_factory do
        %ImageSeries{
          name: "Series name",
          slug: "series-name",
          cfg: %ImageConfig{sizes: @sizes, upload_path: "portfolio/test-category/test-series"},
          sequence: 0,
          image_category: build(:image_category),
          creator: build(:user)
        }
      end

      def image_category_factory do
        %ImageCategory{
          cfg: %ImageConfig{sizes: @sizes, upload_path: "portfolio/test-category"},
          name: "Test Category",
          slug: "test-category",
          creator: build(:user)
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
          allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
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
            "micro" => %{"size" => "25x25", "quality" => 100, "crop" => true}
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
  end
end
