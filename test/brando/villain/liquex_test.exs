defmodule Brando.Villain.LiquexTest do
  use ExUnit.Case, async: true
  use Brando.ConnCase
  alias Brando.Factory

  test "if statement" do
    Brando.Cache.Globals.set()

    global_category_params = %{
      "label" => "System",
      "key" => "system",
      "globals" => [
        %{type: "text", label: "Text", key: "text", value: "My text"},
        %{type: "boolean", label: "Text", key: "boolean", value: false}
      ]
    }

    {:ok, _gc1} = Brando.Globals.create_global_category(global_category_params, :system)

    context = Brando.Villain.get_base_context()

    html =
      """
      {% if globals.system.text == "My text" %}
        Matches!
      {% endif %}
      """
      |> String.trim()
      |> Brando.Villain.parse_and_render(context)

    assert html == "\n  Matches!\n"

    html =
      """
      {% if globals.system.boolean %}
        Matches!
      {% else %}
        Boolean is false
      {% endif %}
      """
      |> String.trim()
      |> Brando.Villain.parse_and_render(context)

    assert html == "\n  Boolean is false\n"
  end

  test "route tag" do
    tpl =
      """
      the route is {% route project_path index %}
      """
      |> String.trim()

    {:ok, parsed_tpl} = Liquex.parse(tpl, Brando.Villain.LiquexParser)

    assert parsed_tpl == [
             {:text, "the route is "},
             {{:custom_tag, Brando.Villain.Tags.Route},
              [function: "project_path", action: "index"]}
           ]

    # render it
    {result, _} = Liquex.Render.render([], parsed_tpl, Brando.Villain.get_base_context())
    assert Enum.join(result) == "the route is /projects"

    tpl =
      """
      the route is {% route project_path show { entry.uri } %}
      """
      |> String.trim()

    {:ok, parsed_tpl} = Liquex.parse(tpl, Brando.Villain.LiquexParser)

    assert parsed_tpl == [
             {:text, "the route is "},
             {{:custom_tag, Brando.Villain.Tags.Route},
              [
                function: "project_path",
                action: "show",
                args: [field: [key: "entry", key: "uri"]]
              ]}
           ]

    entry = %{uri: "the-uri"}
    context = Brando.Villain.get_base_context(entry)
    {result, _} = Liquex.Render.render([], parsed_tpl, context)
    assert Enum.join(result) == "the route is /project/the-uri"

    tpl =
      """
      the route is {% route project_path show { entry.uri, entry.id } %}
      """
      |> String.trim()

    {:ok, parsed_tpl} = Liquex.parse(tpl, Brando.Villain.LiquexParser)

    assert parsed_tpl == [
             {:text, "the route is "},
             {{:custom_tag, Brando.Villain.Tags.Route},
              [
                function: "project_path",
                action: "show",
                args: [field: [key: "entry", key: "uri"], field: [key: "entry", key: "id"]]
              ]}
           ]

    entry = %{uri: "the-uri", id: 500}
    context = Brando.Villain.get_base_context(entry)
    {result, _} = Liquex.Render.render([], parsed_tpl, context)
    assert Enum.join(result) == "the route is /project/the-uri/500"
  end

  test "picture tag" do
    tpl =
      """
      {% picture entry.cover %}
      """
      |> String.trim()

    {:ok, parsed_tpl} = Liquex.parse(tpl, Brando.Villain.LiquexParser)

    assert parsed_tpl == [
             {{:custom_tag, Brando.Villain.Tags.Picture},
              [source: {:field, [key: "entry", key: "cover"]}]}
           ]

    tpl =
      """
      {% picture entry.avatar { size: \"auto\", lazyload: true, srcset: "Brando.Users.User:avatar" } %}
      """
      |> String.trim()

    {:ok, parsed_tpl} = Liquex.parse(tpl, Brando.Villain.LiquexParser)

    assert parsed_tpl == [
             {
               {:custom_tag, Brando.Villain.Tags.Picture},
               [
                 source: {:field, [key: "entry", key: "avatar"]},
                 args: [
                   keyword: ["size", {:literal, "auto"}],
                   keyword: ["lazyload", {:literal, true}],
                   keyword: ["srcset", {:literal, "Brando.Users.User:avatar"}]
                 ]
               ]
             }
           ]

    user = Factory.insert(:random_user)
    context = Brando.Villain.get_base_context(user)
    {result, _} = Liquex.Render.render([], parsed_tpl, context)

    assert Enum.join(result) ==
             "<picture data-ll-srcset data-orientation=\"landscape\"><source data-srcset=\"images/avatars/small/27i97a.jpeg 300w, images/avatars/medium/27i97a.jpeg 500w, images/avatars/large/27i97a.jpeg 700w\" type=\"image/jpeg\"><img data-ll-placeholder data-ll-srcset-image data-src=\"images/avatars/small/27i97a.jpeg\" data-srcset=\"images/avatars/small/27i97a.jpeg 300w, images/avatars/medium/27i97a.jpeg 500w, images/avatars/large/27i97a.jpeg 700w\" height=\"200\" width=\"300\"><noscript><img src=\"images/avatars/small/27i97a.jpeg\"></noscript></picture>"
  end
end
