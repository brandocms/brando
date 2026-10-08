defmodule Brando.Docs.AgentsTest do
  # Compiles examples into global module names, so not async.
  use ExUnit.Case, async: false

  alias Brando.UsageRulesExamples
  alias Mix.Brando.Docs.Agents

  @root Path.expand("../../..", __DIR__)

  setup_all do
    %{guides: Agents.guides(@root, Mix.Project.config()[:docs])}
  end

  describe "usage-rules.md" do
    test "is up to date with the guides", %{guides: guides} do
      assert File.read!(Path.join(@root, "usage-rules.md")) == Agents.usage_rules(guides),
             "usage-rules.md is out of date. Run mix brando.docs.agents and commit the result."
    end

    test "is reproducible", %{guides: guides} do
      again = Agents.guides(@root, Mix.Project.config()[:docs])

      assert Agents.usage_rules(guides) == Agents.usage_rules(again)
      assert Agents.llms_txt(guides) == Agents.llms_txt(again)
      assert Agents.llms_full_txt(guides) == Agents.llms_full_txt(again)
    end

    test "points every section at a guide that ships with the package", %{guides: guides} do
      rules = Agents.usage_rules(guides)

      for [_, file] <- Regex.scan(~r{^Guide: `deps/brando/guides/([a-z0-9_]+\.md)`$}m, rules) do
        assert File.exists?(Path.join([@root, "guides", file]))
      end

      for [_, file] <- Regex.scan(~r{\]\(deps/brando/guides/([a-z0-9_]+\.md)}, rules) do
        assert File.exists?(Path.join([@root, "guides", file])), "usage-rules.md links to a missing guide: #{file}"
      end
    end

    test "every Elixir example compiles, or is marked as not compilable", %{guides: guides} do
      UsageRulesExamples.define_scratch_modules()
      examples = guides |> Agents.usage_rules() |> Agents.examples()

      assert examples != []

      failures =
        for example <- examples, not example.no_compile, {:error, reason} <- [UsageRulesExamples.check(example.code)] do
          "usage-rules.md:#{example.line} (#{example.section})\n#{indent(reason)}\n\n#{indent(example.code)}"
        end

      assert failures == [], """
      #{length(failures)} example(s) in usage-rules.md fail. Fix the guide the example comes from, or put
      #{Agents.no_compile_marker()} on the line before an example that cannot compile.

      #{Enum.join(failures, "\n\n")}
      """
    end
  end

  describe "examples check" do
    test "rejects a Brando function that does not exist" do
      assert {:error, reason} = UsageRulesExamples.check("Brando.Pages.get_pages_by_magic(%{})")
      assert reason =~ "Brando.Pages.get_pages_by_magic/1 is undefined"
    end

    test "rejects a wrong arity, through an alias and a pipe" do
      code = """
      alias Brando.Pages
      %{matches: %{key: "index"}} |> Pages.get_page(:extra, :args)
      """

      assert {:error, reason} = UsageRulesExamples.check(code)
      assert reason =~ "Brando.Pages.get_page/3 is undefined"
    end

    test "rejects a capture of an undefined function and a missing module" do
      assert {:error, reason} = UsageRulesExamples.check("&Brando.Pages.get_page/9")
      assert reason =~ "get_page/9"
      assert {:error, reason} = UsageRulesExamples.check("Brando.NoSuchModule")
      assert reason =~ "Brando.NoSuchModule does not exist"
    end

    test "compiles Blueprint DSL fragments inside a scratch Blueprint" do
      UsageRulesExamples.define_scratch_modules()

      assert {:ok, :blueprint} = UsageRulesExamples.check("attribute :title, :string, required: true")

      assert {:error, reason} = UsageRulesExamples.check("attribute :title, :string, no_such_option: true")
      assert reason =~ "no_such_option"
    end

    test "parses other expressions without running them" do
      assert {:ok, :expression} = UsageRulesExamples.check("MyApp.Articles.list_articles(%{status: :published})")
      assert {:error, reason} = UsageRulesExamples.check("MyApp.Articles.list_articles(")
      assert reason =~ "does not parse"
    end
  end

  describe "llms.txt" do
    test "has a title, a summary and a link with a description for every guide", %{guides: guides} do
      llms = Agents.llms_txt(guides)

      assert llms =~ ~r/\A# Brando\n\n> \S/
      assert guides != []

      for guide <- guides do
        assert llms =~ "- [#{guide.title}](#{guide.id}.md): ", "llms.txt has no entry for #{guide.path}"
        assert guide.description != ""
      end

      assert llms =~ "(llms-full.txt)"
    end

    test "llms-full.txt joins every guide without the markers", %{guides: guides} do
      full = Agents.llms_full_txt(guides)

      for guide <- guides, do: assert(full =~ "<!-- guides/#{guide.file} -->")
      refute full =~ "usage-rules:start"
      refute full =~ "usage-rules:no-compile"
      refute full =~ "llms-description:"
    end
  end

  defp indent(text), do: text |> String.split("\n") |> Enum.map_join("\n", &("    " <> &1))
end
