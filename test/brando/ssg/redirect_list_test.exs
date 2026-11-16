defmodule Brando.SSG.RedirectListTest do
  use ExUnit.Case, async: true

  alias Brando.Sites.Redirect
  alias Brando.SSG.RedirectList

  test "names the languages and the default language it was made with" do
    assert {list, []} = RedirectList.build([], [], [])

    assert %{"version" => 1, "languages" => languages, "default_language" => default} =
             list |> Jason.encode!() |> Jason.decode!()

    assert languages == Brando.Languages.codes()
    assert default == to_string(Brando.Languages.default_language())
  end

  test "a relative target is resolved against its source before the query-only check" do
    rules = [{"en", %Redirect{from: "/docs/start$", to: "docs/start?ref=old", code: 301}}]

    assert {list, []} = RedirectList.build([], ["/docs/docs/start"], rules)

    assert [%{"source" => "/docs/start", "target" => "docs/start?ref=old"}] =
             list |> Jason.encode!() |> Jason.decode!() |> Map.fetch!("redirects")
  end

  test "a relative target that resolves to its own source differs only by the query" do
    rules = [{"en", %Redirect{from: "/docs/start$", to: "start?ref=old", code: 301}}]

    assert {list, [note]} = RedirectList.build([], ["/docs/start"], rules)
    assert note =~ "differs from its source only by the query"
    assert %{"redirects" => []} = list |> Jason.encode!() |> Jason.decode!()
  end

  test "a listed redirect to its own encoded path with a query is left out" do
    page_redirects = [%{source: "/café", target: "/caf%C3%A9?lang=en", status: 302}]

    assert {list, [note]} = RedirectList.build(page_redirects, ["/café"], [])
    assert note =~ "differs from its source only by the query"
    assert %{"redirects" => []} = list |> Jason.encode!() |> Jason.decode!()
  end
end
