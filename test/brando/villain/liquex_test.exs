defmodule Brando.Villain.LiquexTest do
  use ExUnit.Case, async: true
  use Brando.ConnCase
  alias Brando.Factory
  doctest Brando.Villain.Filters

  setup do
    preserve_cache(:globals)
  end

  test "if statement" do
    Brando.Cache.Globals.set()

    global_set_params = %{
      "label" => "System",
      "key" => "system",
      "language" => "en",
      "vars" => [
        %{type: "text", label: "Text", key: "text", value: "My text"},
        %{type: "boolean", label: "Text", key: "boolean", value_boolean: false}
      ]
    }

    usr = Factory.insert(:random_user)
    {:ok, _gc1} = Brando.Sites.create_global_set(global_set_params, usr)
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

  test "fragment tag renders a published fragment and nothing for an unpublished one" do
    Factory.insert(:fragment, parent_key: "partials", key: "footer", language: "en", rendered_blocks: "Footer")

    Factory.insert(:fragment,
      parent_key: "partials",
      key: "draft",
      language: "en",
      status: :draft,
      rendered_blocks: "Draft"
    )

    render = fn key ->
      {:ok, parsed_tpl} = Liquex.parse("{% fragment partials #{key} en %}", Brando.Villain.LiquexParser)
      {result, _} = Liquex.Render.render!([], parsed_tpl, Brando.Villain.get_base_context())
      Enum.join(result)
    end

    assert render.("footer") == "Footer"
    assert render.("draft") == ""

    # The tag renders into an entry's stored HTML, which visitors see: a
    # mistyped key is logged, not shown.
    assert render.("missing") == ""
  end

  test "a fragment placeholder in a container renders nothing for a missing fragment" do
    Factory.insert(:fragment, parent_key: "partials", key: "footer", language: "en", rendered_blocks: "Footer")

    assert Brando.Villain.Parser.replace_fragments("{% fragment partials footer en %}|{% fragment partials missing en %}") ==
             "Footer|"
  end

  test "link tag prints its text as text, as <.entry_link> does" do
    render = fn var -> Brando.Villain.parse_and_render("{% link cta %}", Liquex.Context.new(%{"cta" => var})) end
    label = ~s(<img src=x onerror="document.title='MARKER'"> & more)

    url_var = %Brando.Content.Var{type: :link, key: "cta", link_type: :url, value: "/about", link_text: label}
    html = render.(url_var)
    refute html =~ "<img"
    assert html =~ "&lt;img src=x onerror=&quot;document.title=&#39;MARKER&#39;&quot;&gt; &amp; more</a>"

    # Without a text of its own, an entry link shows the entry's title
    identifier_var = %Brando.Content.Var{
      type: :link,
      key: "cta",
      link_type: :identifier,
      link_text: nil,
      identifier: %{url: "/rooms", title: "Rooms <b>& suites</b>"}
    }

    assert render.(identifier_var) =~ ">Rooms &lt;b&gt;&amp; suites&lt;/b&gt;</a>"
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
             {{:tag, Brando.Villain.Tags.Route}, [function: "project_path", action: "index"]}
           ]

    # render it
    {result, _} = Liquex.Render.render!([], parsed_tpl, Brando.Villain.get_base_context())
    assert Enum.join(result) == "the route is /projects"

    tpl =
      """
      the route is {% route project_path show { entry.uri } %}
      """
      |> String.trim()

    {:ok, parsed_tpl} = Liquex.parse(tpl, Brando.Villain.LiquexParser)

    assert parsed_tpl == [
             {:text, "the route is "},
             {{:tag, Brando.Villain.Tags.Route},
              [
                function: "project_path",
                action: "show",
                args: [field: [key: "entry", key: "uri"]]
              ]}
           ]

    entry = %{uri: "the-uri"}
    context = Brando.Villain.get_base_context(entry)
    {result, _} = Liquex.Render.render!([], parsed_tpl, context)
    assert Enum.join(result) == "the route is /project/the-uri"

    tpl =
      """
      the route is {% route project_path show { entry.uri, entry.id } %}
      """
      |> String.trim()

    {:ok, parsed_tpl} = Liquex.parse(tpl, Brando.Villain.LiquexParser)

    assert parsed_tpl == [
             {:text, "the route is "},
             {{:tag, Brando.Villain.Tags.Route},
              [
                function: "project_path",
                action: "show",
                args: [field: [key: "entry", key: "uri"], field: [key: "entry", key: "id"]]
              ]}
           ]

    entry = %{uri: "the-uri", id: 500}
    context = Brando.Villain.get_base_context(entry)
    {result, _} = Liquex.Render.render!([], parsed_tpl, context)
    assert Enum.join(result) == "the route is /project/the-uri/500"
  end

  test "picture tag renders the image of a gallery object" do
    image = %Brando.Images.Image{
      path: "images/gallery/boat.jpg",
      sizes: %{"small" => "images/gallery/small/boat.jpg"},
      width: 300,
      height: 200,
      alt: %{"en" => "A boat"},
      config_target: "default"
    }

    tpl = "{% for image in images %}{% picture image { key: 'small', language: 'en' } %}{% endfor %}"
    {:ok, parsed_tpl} = Liquex.parse(tpl, Brando.Villain.LiquexParser)

    context =
      %{}
      |> Brando.Villain.get_base_context()
      |> Liquex.Context.assign("images", [%Brando.Galleries.GalleryObject{image: image}])

    {result, _} = Liquex.Render.render!([], parsed_tpl, context)

    assert Enum.join(result) =~ ~s(alt="A boat")
  end

  test "picture tag" do
    tpl =
      """
      {% picture entry.cover %}
      """
      |> String.trim()

    {:ok, parsed_tpl} = Liquex.parse(tpl, Brando.Villain.LiquexParser)

    assert parsed_tpl == [
             {{:tag, Brando.Villain.Tags.Picture}, [source: {:field, [key: "entry", key: "cover"]}]}
           ]

    tpl =
      """
      {% picture entry.avatar { size: \"auto\", lazyload: true, srcset: "Brando.Users.User:avatar" } %}
      """
      |> String.trim()

    {:ok, parsed_tpl} = Liquex.parse(tpl, Brando.Villain.LiquexParser)

    assert parsed_tpl == [
             {
               {:tag, Brando.Villain.Tags.Picture},
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
    {result, _} = Liquex.Render.render!([], parsed_tpl, context)

    doc =
      result
      |> Enum.join()
      |> Floki.parse_document!()

    assert doc
           |> Floki.find("picture > img")
           |> assert_attr("height", ["200"])
           |> assert_attr("width", ["300"])
           |> assert_attr("alt", [""])
           |> assert_attr("data-ll-srcset-image", ["data-ll-srcset-image"])

    assert doc
           |> Floki.find("figure")
           |> assert_attr("data-orientation", ["landscape"])
  end
end
