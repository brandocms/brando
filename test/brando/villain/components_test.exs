defmodule Brando.Villain.ComponentsTest do
  use ExUnit.Case, async: false
  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]
  alias Brando.Villain.Components
  alias Brando.Villain.HeexRenderer

  defmodule RouteWeb.Router.Helpers do
    def no_project_path(_endpoint, :index), do: "/no/prosjekter"
  end

  defmodule RouteWeb.Endpoint do
  end

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

  describe "video/1" do
    test "passes the source to the Brando video component" do
      assigns = %{src: "https://cdn.example/video.mp4", opts: [controls: true], __changed__: %{}}
      result = rendered_to_string(Components.video(assigns))

      assert result =~ ~s(<video)
      assert result =~ ~s(src="https://cdn.example/video.mp4")
      assert result =~ ~s(controls)
    end
  end

  describe "ref/1" do
    test "headless refs render no published parser output" do
      assigns = headless_ref_assigns()
      assert Components.ref(assigns) |> rendered_to_string() |> String.trim() == ""
    end

    test "headless refs yield their data to a custom slot" do
      code = """
      <.ref block={@block} ref={:body} headless :let={data}>
        <strong>{data.text}</strong>
      </.ref>
      """

      result =
        HeexRenderer.render_to_string("headless_ref_slot", code, %{
          block: %{module_id: 123},
          _heex_ctx: headless_ref_context()
        })

      assert result =~ "<strong>Custom body</strong>"
      refute result =~ "paragraph"
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

    test "renders link vars with their configured text and target" do
      assigns = %{
        href: nil,
        entry: nil,
        field: :url,
        var: %Brando.Content.Var{
          type: :link,
          link_type: :url,
          value: "https://brandocms.com",
          link_text: "Brando",
          link_target_blank: true
        },
        class: nil,
        inner_block: [],
        __changed__: %{}
      }

      result = rendered_to_string(Components.entry_link(assigns))

      assert result =~ ~s(href="https://brandocms.com")
      assert result =~ ~s(target="_blank")
      assert result =~ ~s(class="link")
      assert result =~ "Brando"
    end
  end

  describe "route/1" do
    test "handles nested page URIs like the Villain route tag" do
      assigns = %{
        helper: :page_path,
        action: :show,
        args: ["about/team"],
        __changed__: %{}
      }

      assert Components.route(assigns) |> rendered_to_string() |> String.trim() == "/about/team"
    end
  end

  describe "route_i18n/1" do
    test "handles nested page URIs like the Villain route_i18n tag" do
      assigns = %{
        helper: :page_path,
        action: :show,
        args: ["about/team"],
        language: "no",
        __changed__: %{}
      }

      assert Components.route_i18n(assigns) |> rendered_to_string() |> String.trim() == "/about/team"
    end

    test "localizes non-page route helpers" do
      original_web_module = Application.fetch_env!(:brando, :web_module)
      Application.put_env(:brando, :web_module, __MODULE__.RouteWeb)
      on_exit(fn -> Application.put_env(:brando, :web_module, original_web_module) end)

      assigns = %{
        helper: :project_path,
        action: :index,
        args: [],
        language: "no",
        __changed__: %{}
      }

      assert Components.route_i18n(assigns) |> rendered_to_string() |> String.trim() == "/no/prosjekter"
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

    test "supports configured languages through a translations map" do
      assigns = %{
        no: "Hei",
        en: "Hello",
        translations: %{"fr" => "Bonjour"},
        language: "fr",
        __changed__: %{}
      }

      result = rendered_to_string(Components.t(assigns))
      assert result =~ "Bonjour"
    end
  end

  defp headless_ref_assigns do
    %{
      block: %{module_id: 123},
      ref: :body,
      headless: true,
      _heex_ctx: headless_ref_context(),
      inner_block: [],
      __changed__: %{}
    }
  end

  defp headless_ref_context do
    %{
      refs: %{
        "body" => %{
          data: %{type: "text", data: %{text: "Custom body", type: :paragraph}},
          description: "Body"
        }
      },
      render_context: :publish,
      parser_module: Brando.Villain.Parser,
      liquex_context: Liquex.Context.new(%{})
    }
  end
end
