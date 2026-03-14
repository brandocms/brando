defmodule Brando.Villain.ComponentsTest do
  use ExUnit.Case, async: false
  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]
  alias Brando.Villain.Components

  describe "content/1" do
    test "renders raw content" do
      assigns = %{content: "<p>Hello <strong>World</strong></p>", __changed__: %{}}
      result = rendered_to_string(Components.content(assigns))
      assert result =~ "<p>Hello <strong>World</strong></p>"
    end
  end

  describe "picture/1" do
    test "renders with nil src" do
      assigns = %{src: nil, opts: [], __changed__: %{}}
      result = rendered_to_string(Components.picture(assigns))
      assert result == ""
    end
  end

  describe "entry_link/1" do
    test "renders link with href" do
      assigns = %{
        href: "/projects/my-project",
        entry: nil,
        field: :url,
        inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Click me" end}],
        __changed__: %{}
      }

      result = rendered_to_string(Components.entry_link(assigns))
      assert result =~ ~s(href="/projects/my-project")
      assert result =~ "Click me"
    end
  end

  describe "fragment/1" do
    # Fragment rendering requires DB connection (Brando.ConnCase), skipping unit test
    # since it queries the fragments table. Tested via integration tests.
  end

  describe "t/1" do
    test "returns Norwegian text for 'no' language" do
      assigns = %{no: "Hei", en: "Hello", language: "no", __changed__: %{}}
      result = rendered_to_string(Components.t(assigns))
      assert result =~ "Hei"
    end

    test "returns English text for 'en' language" do
      assigns = %{no: "Hei", en: "Hello", language: "en", __changed__: %{}}
      result = rendered_to_string(Components.t(assigns))
      assert result =~ "Hello"
    end

    test "defaults to English for unknown language" do
      assigns = %{no: "Hei", en: "Hello", language: "de", __changed__: %{}}
      result = rendered_to_string(Components.t(assigns))
      assert result =~ "Hello"
    end
  end
end
