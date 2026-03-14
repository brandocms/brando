defmodule Brando.Villain.HeexRendererTest do
  use ExUnit.Case, async: false
  alias Brando.Villain.HeexRenderer

  describe "compile_module!/2" do
    test "compiles a simple HEEx template" do
      module = HeexRenderer.compile_module!("test_simple", "<h1>Hello</h1>")
      assert is_atom(module)
      assert function_exported?(module, :render, 1)
    end

    test "compiles template with assigns" do
      module = HeexRenderer.compile_module!("test_assigns", "<h1><%= @title %></h1>")
      assert is_atom(module)
    end

    test "recompiles when called again with same id" do
      mod1 = HeexRenderer.compile_module!("test_recompile", "<h1>V1</h1>")
      mod2 = HeexRenderer.compile_module!("test_recompile", "<h1>V2</h1>")
      assert mod1 == mod2
    end
  end

  describe "get_or_compile!/2" do
    test "returns cached module on second call with same code" do
      HeexRenderer.invalidate("test_cache")
      mod1 = HeexRenderer.get_or_compile!("test_cache", "<p>cached</p>")
      mod2 = HeexRenderer.get_or_compile!("test_cache", "<p>cached</p>")
      assert mod1 == mod2
    end

    test "recompiles when code changes" do
      HeexRenderer.invalidate("test_cache_change")
      mod1 = HeexRenderer.get_or_compile!("test_cache_change", "<p>v1</p>")
      mod2 = HeexRenderer.get_or_compile!("test_cache_change", "<p>v2</p>")
      # Different code hash means different cache key, both are compiled
      # Same module name since same id
      assert mod1 == mod2
    end
  end

  describe "render_to_string/3" do
    test "renders simple static template" do
      result = HeexRenderer.render_to_string("test_render_static", "<div>hello</div>", %{})
      assert result =~ "hello"
      assert result =~ "<div>"
    end

    test "renders template with assigns" do
      result =
        HeexRenderer.render_to_string(
          "test_render_assigns",
          "<h1><%= @title %></h1>",
          %{title: "My Title"}
        )

      assert result =~ "My Title"
      assert result =~ "<h1>"
    end

    test "renders template with conditional" do
      code = """
      <%= if @show do %>
        <p>visible</p>
      <% else %>
        <p>hidden</p>
      <% end %>
      """

      result = HeexRenderer.render_to_string("test_conditional", code, %{show: true})
      assert result =~ "visible"
      refute result =~ "hidden"

      result = HeexRenderer.render_to_string("test_conditional_false", code, %{show: false})
      assert result =~ "hidden"
      refute result =~ "visible"
    end

    test "renders template with for comprehension" do
      code = """
      <ul>
        <%= for item <- @items do %>
          <li><%= item %></li>
        <% end %>
      </ul>
      """

      result =
        HeexRenderer.render_to_string(
          "test_for",
          code,
          %{items: ["a", "b", "c"]}
        )

      assert result =~ "<li>a</li>"
      assert result =~ "<li>b</li>"
      assert result =~ "<li>c</li>"
    end

    test "renders template with render_context check" do
      code = """
      <%= if @render_context == :admin do %>
        <div>admin mode</div>
      <% else %>
        <div>publish mode</div>
      <% end %>
      """

      result =
        HeexRenderer.render_to_string("test_ctx_admin", code, %{render_context: :admin})

      assert result =~ "admin mode"

      result =
        HeexRenderer.render_to_string("test_ctx_publish", code, %{render_context: :publish})

      assert result =~ "publish mode"
    end
  end

  describe "invalidate/1" do
    test "invalidates cached module for given id" do
      HeexRenderer.get_or_compile!("test_invalidate", "<p>test</p>")
      assert :ok = HeexRenderer.invalidate("test_invalidate")
    end
  end

  describe "invalidate_all/0" do
    test "clears all cached modules" do
      HeexRenderer.get_or_compile!("test_inv_all_1", "<p>1</p>")
      HeexRenderer.get_or_compile!("test_inv_all_2", "<p>2</p>")
      assert :ok = HeexRenderer.invalidate_all()
    end
  end
end
