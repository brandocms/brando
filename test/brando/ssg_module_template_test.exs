defmodule Brando.SSGModuleTemplateTest do
  use Brando.ConnCase

  alias Brando.Factory

  @template "priv/templates/brando.gen.ssg/lib/application_name_web/ssg.ex"
  @guide "guides/tenancy_and_environments.md"

  defp render(web_module), do: EEx.eval_string(File.read!(@template), web_module: web_module)

  # The guide's SSG module, the first Elixir block defining one
  defp guide_example do
    [_whole, code] = Regex.run(~r/```elixir\n(defmodule MyAppWeb\.SSG do\n.*?)```/s, File.read!(@guide))
    code
  end

  test "the guide shows the module mix brando.gen.ssg writes" do
    assert guide_example() == render("MyAppWeb")
  end

  test "the generated module compiles without a warning, type warnings included" do
    source = render("BrandoSSGTemplateProbeWeb")

    {modules, diagnostics} = Code.with_diagnostics(fn -> Code.compile_string(source, @template) end)
    on_exit(fn -> Enum.each(modules, fn {module, _} -> :code.purge(module) && :code.delete(module) end) end)

    assert diagnostics == []
  end

  test "the generated module lists the published pages that have a URL, from the content" do
    [{module, _}] = Code.compile_string(render("BrandoSSGTemplateListWeb"), @template)
    on_exit(fn -> :code.purge(module) && :code.delete(module) end)

    Factory.insert(:page, uri: "index")
    Factory.insert(:page, uri: "about")
    Factory.insert(:page, uri: "draft", status: :draft)
    Factory.insert(:page, uri: "404", has_url: false)

    # Drafts and pages without a URL (the 404 page) are left out
    assert {:ok, urls} = Brando.SSG.get_urls(module)
    assert Enum.sort(urls) == ["/en/", "/en/about"]
  end
end
