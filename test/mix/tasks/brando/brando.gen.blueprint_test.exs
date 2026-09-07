defmodule Mix.Tasks.Brando.Gen.BlueprintTest do
  use ExUnit.Case, async: false

  alias Brando.IgniterCase
  alias Mix.Tasks.Brando.Gen.Blueprint

  defp generate(igniter, args), do: Igniter.compose_task(igniter, Blueprint, args)

  test "uses source namespaces and current Blueprint fields, listings and forms" do
    igniter = IgniterCase.phoenix_project(app: :shop, module: "Acme.Shop", web: "Acme.Web")
    result = generate(igniter, ["Catalog", "Product", "--admin-module", "Acme.Backoffice"])
    assert result.issues == []
    source = IgniterCase.source(result, "lib/acme/shop/catalog/product.ex")
    assert source =~ "defmodule Acme.Shop.Catalog.Product"
    assert source =~ "backend: Acme.Backoffice.Gettext"
    assert source =~ ~s(singular: "product")
    assert source =~ ~s(:title, :string, required: true)
    assert source =~ "listing_row"
    assert source =~ "absolute_url(false)"
    assert source =~ "forms do"
    refute_received {:mix_shell, :prompt, _}
    assert result.tasks == []
  end

  test "accepts naming overrides and nested domains" do
    result = IgniterCase.phoenix_project() |> generate(["Directory.People", "Person", "--plural", "people"])
    assert result.issues == []
    source = IgniterCase.source(result, "lib/studio/directory/people/person.ex")
    assert source =~ ~s(plural: "people")
    assert source =~ ~s(domain: "Directory.People")
  end

  test "reruns preserve the existing Blueprint and comments" do
    generated = IgniterCase.phoenix_project() |> generate(["Catalog", "Product"])
    path = "lib/studio/catalog/product.ex"
    source = "# Keep this comment\n" <> IgniterCase.source(generated, path)
    rerun = IgniterCase.phoenix_project(files: %{path => source}) |> generate(["Catalog", "Product"])
    assert rerun.issues == []
    Igniter.Test.assert_unchanged(rerun, path)
  end

  test "customized Blueprint content blocks overwrite even with yes" do
    path = "lib/studio/catalog/product.ex"

    result =
      IgniterCase.phoenix_project(files: %{path => "defmodule Studio.Catalog.Product do\n def custom, do: true\nend"})
      |> generate(["Catalog", "Product", "--yes"])

    assert Enum.any?(result.issues, &String.contains?(&1, "already contains different content"))
    Igniter.Test.assert_unchanged(result, path)
  end

  test "missing and invalid names fail without a prompt or generated files" do
    for args <- [
          [],
          ["Catalog"],
          ["../Catalog", "Product"],
          ["Catalog", "Nested.Product"],
          ["Catalog", "Product", "--singular", "Product"],
          ["Catalog", "Product", "--plural", "product"]
        ] do
      result = IgniterCase.phoenix_project() |> generate(args)
      assert result.issues != [], inspect(args)
      refute_received {:mix_shell, :prompt, _}
      Igniter.Test.assert_unchanged(result)
    end
  end

  test "interactive mode asks only for missing arguments" do
    Mix.shell(Mix.Shell.Process)
    send(self(), {:mix_shell_input, :prompt, "Product"})
    result = IgniterCase.phoenix_project() |> generate(["Catalog", "--interactive"])
    assert result.issues == []
    assert_received {:mix_shell, :prompt, ["+ Schema"]}
    refute_received {:mix_shell, :prompt, _}
  end

  test "closed interactive input produces an actionable issue" do
    Mix.shell(Mix.Shell.Process)
    send(self(), {:mix_shell_input, :prompt, :eof})
    result = IgniterCase.phoenix_project() |> generate(["--interactive"])
    assert Enum.any?(result.issues, &String.contains?(&1, "Input closed"))
    Igniter.Test.assert_unchanged(result)
  end

  test "explicit and consumer templates take precedence over the packaged default" do
    local = "priv/templates/brando.gen.blueprint/blueprint.ex"
    template = "defmodule <%= app_module %>.<%= domain %>.<%= schema %> do\n def marker, do: :local\nend"

    base =
      IgniterCase.phoenix_project(
        files: %{local => template, "custom.ex.eex" => String.replace(template, ":local", ":explicit")}
      )

    result = generate(base, ["Catalog", "Product"])
    assert result.issues == []
    assert IgniterCase.source(result, "lib/studio/catalog/product.ex") =~ ":local"
    result = generate(base, ["Catalog", "Product", "--template", "custom.ex.eex"])
    assert result.issues == []
    assert IgniterCase.source(result, "lib/studio/catalog/product.ex") =~ ":explicit"
    assert generate(base, ["Catalog", "Product", "--template", "missing.ex.eex"]).issues != []
  end
end
