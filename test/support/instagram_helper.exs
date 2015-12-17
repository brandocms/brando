defmodule Brando.Integration.Instagram do
  @img_fixture "#{Path.expand("..", __DIR__)}/fixtures/sample.jpg"

  # Users
  def get("https://api.instagram.com/v1/users/search?q=asf98293h8a9283fh9a238fh&client_id=CLIENT_ID") do
    {
      :ok,
      %{
        body: [
          meta: %{
            "code" => 400,
            "error_message" => "The client_id provided is invalid and does not match a valid application.",
            "error_type" => "OAuthParameterException"
          }
        ],
        headers: [],
        status_code: 400
      }
    }
  end

  def get("https://api.instagram.com/v1/users/search?q=djasf98293h8a9283fh9a238fh&client_id=CLIENT_ID") do
    {
      :ok,
      %{
        body: [
          data: [],
          meta: %{
            "code" => 200
          }
        ],
        headers: [],
        status_code: 200}
    }
  end

  def get("https://api.instagram.com/v1/users/search?q=dummy_user&client_id=CLIENT_ID") do
    {
      :ok,
      %{
        body: [
          data: [
            %{
              "full_name" => "",
              "id" => "0123456",
              "profile_picture" => "",
              "username" => "dummy_user"
            }
          ],
          meta: %{
            "code" => 200
          }
        ],
        headers: [],
        status_code: 200
    }
    }
  end

  # Media
  def get("https://api.instagram.com/v1/media/968134024444958851_000000?client_id=CLIENT_ID") do
    {
      :ok,
      %{
        body: [
          data: %{
            "caption" => %{
              "created_time" => "1429882830",
              "id" => "970249963802612652",
              "text" => "Caption text. #hashtag1 #hashtag2"
            },
            "created_time" => "1429882830",
            "id" => "970249962242331087_1492879755",
            "images" => %{
              "standard_resolution" => %{
                "height" => 640,
                "url" => "https://scontent.cdninstagram.com/hphotos-xap1/t51.2885-15/e15/11190180_464905646995552_1163060820_n.jpg",
                "width" => 640
              },
              "thumbnail" => %{
                "height" => 150,
                "url" => "https://scontent.cdninstagram.com/hphotos-xap1/t51.2885-15/s150x150/e15/11190180_464905646995552_1163060820_n.jpg",
                "width" => 150
              }
            },
            "link" => "https://instagram.com/p/13BTM2ylHP/",
            "type" => "image",
            "user" => %{
              "username" => "haraball_"
            },
          },
          meta: %{"code" => 200}
        ],
        headers: [],
        status_code: 200
      }
    }
  end

  # Media for users
  def get("https://api.instagram.com/v1/users/0123456/media/recent/?client_id=CLIENT_ID&min_timestamp=0") do
    {
      :ok,
      %{
        body: [
          data: [
            %{
              "caption" => nil,
              "created_time" => "1426980419",
              "id" => "000000000000000000_000000",
              "images" => %{
                "standard_resolution" => %{
                  "height" => 640,
                  "url" => "https://scontent.cdninstagram.com/hphotos-xft1/t51.2885-15/e15/1.jpg",
                  "width" => 640
                },
                "thumbnail" => %{
                  "height" => 150,
                  "url" => "https://scontent.cdninstagram.com/hphotos-xft1/t51.2885-15/s150x150/e15/1.jpg",
                  "width" => 150
                }
              },
              "link" => "https://instagram.com/p/0/",
              "type" => "image",
              "user" => %{
                "full_name" => "",
                "id" => "012345",
                "profile_picture" => "",
                "username" => "dummy_user"
              },
            },
            %{
              "caption" => nil,
              "created_time" => "1412585305",
              "id" => "1111111111111_0123456",
              "images" => %{
                "standard_resolution" => %{
                  "height" => 640,
                  "url" => "https://scontent.cdninstagram.com/hphotos-xpf1/t51.2885-15/e15/0.jpg",
                  "width" => 640
                },
                "thumbnail" => %{
                  "height" => 150,
                  "url" => "https://scontent.cdninstagram.com/hphotos-xpf1/t51.2885-15/s150x150/e15/0.jpg",
                  "width" => 150
                }
              },
              "link" => "https://instagram.com/p/1/",
              "type" => "image",
              "user" => %{
                "full_name" => "",
                "id" => "0123456",
                "profile_picture" => "",
                "username" => "dummy_user"
              },
            }
          ],
          meta: %{
            "code" => 200
          },
          pagination: %{}
        ],
        headers: [],
        status_code: 200
      }
    }
  end

  def get("https://api.instagram.com/v1/users/0123456/media/recent/?client_id=CLIENT_ID&min_timestamp=" <> _ts) do
    {
      :ok,
      %{
        body: [
          data: [
            %{
              "caption" => nil,
              "created_time" => "1426980419",
              "id" => "000000000000000000_000000",
              "images" => %{
                "standard_resolution" => %{
                  "height" => 640,
                  "url" => "https://scontent.cdninstagram.com/hphotos-xft1/t51.2885-15/e15/1.jpg",
                  "width" => 640
                },
                "thumbnail" => %{
                  "height" => 150,
                  "url" => "https://scontent.cdninstagram.com/hphotos-xft1/t51.2885-15/s150x150/e15/1.jpg",
                  "width" => 150
                }
              },
              "link" => "https://instagram.com/p/0/",
              "type" => "image",
              "user" => %{
                "full_name" => "",
                "id" => "012345",
                "profile_picture" => "",
                "username" => "dummy_user"
              },
            },
            %{
              "caption" => nil,
              "created_time" => "1412585305",
              "id" => "1111111111111_0123456",
              "images" => %{
                "standard_resolution" => %{
                  "height" => 640,
                  "url" => "https://scontent.cdninstagram.com/hphotos-xpf1/t51.2885-15/e15/0.jpg",
                  "width" => 640
                },
                "thumbnail" => %{
                  "height" => 150,
                  "url" => "https://scontent.cdninstagram.com/hphotos-xpf1/t51.2885-15/s150x150/e15/0.jpg",
                  "width" => 150
                }
              },
              "link" => "https://instagram.com/p/1/",
              "type" => "image",
              "user" => %{
                "full_name" => "",
                "id" => "0123456",
                "profile_picture" => "",
                "username" => "dummy_user"
              },
              "users_in_photo" => []
            }
          ],
          meta: %{
            "code" => 200
          },
          pagination: %{}
        ],
        headers: [],
        status_code: 200
      }
    }
  end

  def get("https://api.instagram.com/v1/users/0123456/media/recent/?client_id=CLIENT_ID&max_id=968134024444958851") do
    {
      :ok,
      %{
        body: [
          data: [
            %{
              "caption" => nil,
              "created_time" => "1426980419",
              "id" => "000000000000000000_000000",
              "images" => %{
                "standard_resolution" => %{
                  "height" => 640,
                  "url" => "https://scontent.cdninstagram.com/hphotos-xft1/t51.2885-15/e15/1.jpg",
                  "width" => 640
                },
                "thumbnail" => %{
                  "height" => 150,
                  "url" => "https://scontent.cdninstagram.com/hphotos-xft1/t51.2885-15/s150x150/e15/1.jpg",
                  "width" => 150
                }
              },
              "link" => "https://instagram.com/p/0/",
              "type" => "image",
              "user" => %{
                "full_name" => "",
                "id" => "012345",
                "profile_picture" => "",
                "username" => "dummy_user"
              },
            },
            %{
              "caption" => nil,
              "created_time" => "1412585305",
              "id" => "1111111111111_0123456",
              "images" => %{
                "standard_resolution" => %{
                  "height" => 640,
                  "url" => "https://scontent.cdninstagram.com/hphotos-xpf1/t51.2885-15/e15/0.jpg",
                  "width" => 640
                },
                "thumbnail" => %{
                  "height" => 150,
                  "url" => "https://scontent.cdninstagram.com/hphotos-xpf1/t51.2885-15/s150x150/e15/0.jpg",
                  "width" => 150
                }
              },
              "link" => "https://instagram.com/p/1/",
              "type" => "image",
              "user" => %{
                "full_name" => "",
                "id" => "0123456",
                "profile_picture" => "",
                "username" => "dummy_user"
              },
            }
          ],
          meta: %{"code" => 200},
          pagination: %{}
        ],
        headers: [],
        status_code: 200
      }
    }
  end

  # Media for tags
  def get("https://api.instagram.com/v1/tags/haraball/media/recent?client_id=CLIENT_ID&min_tag_id=0") do
    {
      :ok,
      %{
        body: [
          data: [
            %{
              "caption" => %{
                "created_time" => "1429882830",
                "id" => "970249963802612652",
                "text" => "Caption here. #test"
              },
              "created_time" => "1429882830",
              "id" => "970249962242331087_1492879755",
              "images" => %{
                "standard_resolution" => %{
                  "height" => 640,
                  "url" => "https://scontent.cdninstagram.com/hphotos-xap1/t51.2885-15/e15/11190180_464905646995552_1163060820_n.jpg",
                  "width" => 640
                },
                "thumbnail" => %{
                  "height" => 150,
                  "url" => "https://scontent.cdninstagram.com/hphotos-xap1/t51.2885-15/s150x150/e15/11190180_464905646995552_1163060820_n.jpg",
                  "width" => 150
                }
              },
              "link" => "https://instagram.com/p/13BTM2ylHP/",
              "type" => "image",
              "user" => %{
                "full_name" => "HARABALL",
                "id" => "1492879755",
                "profile_picture" => "",
                "username" => "haraball_"
              },
            }
          ],
          meta: %{"code" => 200},
          pagination: %{
            "min_tag_id" => "974770073844008277",
            "next_min_id" => "974770073844008277"
          }
        ],
        headers: [],
        status_code: 200
      }
    }
  end

  def get("https://api.instagram.com/v1/tags/haraball/media/recent?client_id=CLIENT_ID&min_tag_id=" <> _) do
    {
      :ok,
      %{
        body: [
          data: [
            %{
              "attribution" => nil,
              "caption" => %{
                "created_time" => "1429882830",
                "id" => "970249963802612652",
                "text" => "Caption text."
              },
              "created_time" => "1429882830",
              "id" => "970249962242331087_1492879755",
              "images" => %{
                "standard_resolution" => %{
                  "height" => 640,
                  "url" => "https://scontent.cdninstagram.com/hphotos-xap1/t51.2885-15/e15/11190180_464905646995552_1163060820_n.jpg",
                  "width" => 640
                },
                "thumbnail" => %{
                  "height" => 150,
                  "url" => "https://scontent.cdninstagram.com/hphotos-xap1/t51.2885-15/s150x150/e15/11190180_464905646995552_1163060820_n.jpg",
                  "width" => 150
                }
              },
              "link" => "https://instagram.com/p/13BTM2ylHP/",
              "type" => "image",
              "user" => %{
                "full_name" => "HARABALL",
                "id" => "1492879755",
                "profile_picture" => "",
                "username" => "haraball_"
              },
            }
          ],
          meta: %{"code" => 200},
          pagination: %{
            "min_tag_id" => "974770073844008277",
            "next_min_id" => "974770073844008277"
          }
        ],
        headers: [],
        status_code: 200
      }
    }
  end

  # Mock image
  def get(_) do
    body = File.read!(@img_fixture)
    {:ok, %{body: body, status_code: 200}}
  end

  # Access Token
  def get!("https://www.instagram.com/accounts/login/?force_classic_login=&next=/oauth/authorize/%3Fclient_id%3DCLIENT_ID%26redirect_uri%3Dhttp%3A//localhost%26response_type%3Dtoken", _) do
    %{headers: [{"Set-Cookie", "csrftoken=abcdefghijklmnopqrstuvwxyz0123456789; mid=this_is_the_mid_cookie"}]}
  end

  def post!("https://www.instagram.com/accounts/login/?force_classic_login=&next=/oauth/authorize/%3Fclient_id%3DCLIENT_ID%26redirect_uri%3Dhttp%3A//localhost%26response_type%3Dtoken", _data, _headers) do
    %{headers: [{"Set-Cookie", "csrftoken=abcdefghijklmnopqrstuvwxyz0123456789; mid=this_is_the_mid_cookie; sessionid=sessioncookie"},
                {"Location", "http://test.authurl.instagram.com/#access_token=abcd123"}]}
  end

  def post!("http://test.authurl.instagram.com/#access_token=abcd123", _data, _headers) do
    %{headers: [{"Set-Cookie", "csrftoken=abcdefghijklmnopqrstuvwxyz0123456789; mid=this_is_the_mid_cookie; sessionid=sessioncookie"},
                {"Location", "http://test.authurl.instagram.com/#access_token=abcd123"}]}
  end
end