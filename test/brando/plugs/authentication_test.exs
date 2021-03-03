defmodule Brando.Plug.AuthenticationTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Plug.Test

  alias Brando.Plug.Authentication
  alias Brando.Factory

  test "login/verify/logout" do
    conn =
      :post
      |> conn("/login")
      |> Authentication.call(
        guardian_module: BrandoIntegration.Guardian,
        authorization_module: BrandoIntegration.Authorization
      )

    assert conn.status == 401
    assert conn.resp_body == "{\"error\":\"Feil ved innlogging\"}"

    post_body = Poison.encode!(%{"email" => "dummy@dummy.com", "password" => "admin"})

    opts =
      Plug.Parsers.init(
        parsers: [:urlencoded, {:multipart, length: 100_000_000}, :json],
        pass: ["*/*"],
        json_decoder: Phoenix.json_library()
      )

    conn =
      :post
      |> conn("/login", post_body)
      |> put_req_header("content-type", "application/json")
      |> Plug.Parsers.call(opts)
      |> Authentication.call(
        guardian_module: BrandoIntegration.Guardian,
        authorization_module: BrandoIntegration.Authorization
      )

    assert conn.status == 401
    assert conn.resp_body == "{\"error\":\"Feil ved innlogging\"}"

    u1 = Factory.insert(:random_user)

    post_body = Poison.encode!(%{"email" => u1.email, "password" => "admin"})

    opts =
      Plug.Parsers.init(
        parsers: [:urlencoded, {:multipart, length: 100_000_000}, :json],
        pass: ["*/*"],
        json_decoder: Phoenix.json_library()
      )

    conn =
      :post
      |> conn("/login", post_body)
      |> put_req_header("content-type", "application/json")
      |> Plug.Parsers.call(opts)
      |> Authentication.call(
        guardian_module: BrandoIntegration.Guardian,
        authorization_module: BrandoIntegration.Authorization
      )

    assert conn.status == 201

    assert Jason.decode!(conn.resp_body) == %{
             "jwt" => "user:#{u1.id}",
             "rules" => [
               %{
                 "action" => "manage",
                 "conditions" => nil,
                 "inverted" => false,
                 "subject" => "all"
               }
             ],
             "config" => %{
               "reset_password_on_first_login" => true,
               "show_onboarding" => false,
               "show_mutation_notifications" => true
             },
             "last_login" => nil
           }

    post_body = Poison.encode!(%{"jwt" => "user:#{u1.id}"})

    conn =
      :post
      |> conn("/verify", post_body)
      |> put_req_header("content-type", "application/json")
      |> Plug.Parsers.call(opts)
      |> Authentication.call(
        guardian_module: BrandoIntegration.Guardian,
        authorization_module: BrandoIntegration.Authorization
      )

    assert conn.status == 200

    assert Poison.decode!(conn.resp_body) == %{
             "ok" => true,
             "rules" => [
               %{
                 "action" => "manage",
                 "conditions" => nil,
                 "inverted" => false,
                 "subject" => "all"
               }
             ]
           }

    conn =
      :post
      |> conn("/logout", post_body)
      |> put_req_header("content-type", "application/json")
      |> Plug.Parsers.call(opts)
      |> Authentication.call(
        guardian_module: BrandoIntegration.Guardian,
        authorization_module: BrandoIntegration.Authorization
      )

    assert conn.status == 200

    assert Poison.decode!(conn.resp_body) == %{"ok" => true}
  end
end
