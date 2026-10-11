defmodule Brando.Assets.Vite.ManifestTest do
  use ExUnit.Case, async: true

  alias Brando.Assets.Vite.Manifest

  test "Vite 5+ names the critical entry" do
    manifest = %{
      "js/critical.js" => %{
        "file" => "assets/critical-abc.js",
        "name" => "critical",
        "src" => "js/critical.js",
        "isEntry" => true,
        "css" => ["assets/critical-def.css"]
      },
      "js/app.js" => %{
        "file" => "assets/app-123.js",
        "name" => "app",
        "src" => "js/app.js",
        "isEntry" => true,
        "css" => ["assets/app-456.css"]
      }
    }

    parsed = Manifest.parse(manifest)

    assert parsed.critical == %{css_files: ["/assets/critical-def.css"], files: ["/assets/critical-abc.js"]}
    assert parsed.entries == %{css_files: ["/assets/app-456.css"], files: ["/assets/app-123.js"]}
  end

  test "Vite 3 and 4 write no name, so the critical entry is found by its key" do
    manifest = %{
      "js/critical.js" => %{
        "file" => "assets/critical.0f1e2d.js",
        "src" => "js/critical.js",
        "isEntry" => true,
        "css" => ["assets/critical.9a8b7c.css"]
      },
      "js/app.js" => %{
        "file" => "assets/app.3c4d5e.js",
        "src" => "js/app.js",
        "isEntry" => true,
        "imports" => ["_vendor.6f7a8b.js"],
        "css" => ["assets/app.1a2b3c.css"]
      },
      "_vendor.6f7a8b.js" => %{"file" => "assets/vendor.6f7a8b.js"},
      "js/app-legacy.js" => %{
        "file" => "assets/app-legacy.4d5e6f.js",
        "src" => "js/app-legacy.js",
        "isEntry" => true
      }
    }

    parsed = Manifest.parse(manifest)

    assert parsed.critical == %{css_files: ["/assets/critical.9a8b7c.css"], files: ["/assets/critical.0f1e2d.js"]}
    assert parsed.entries == %{css_files: ["/assets/app.1a2b3c.css"], files: ["/assets/app.3c4d5e.js"]}
    assert parsed.legacy == %{files: ["/assets/app-legacy.4d5e6f.js"]}
  end

  test "a named entry is not taken for critical by its key" do
    manifest = %{
      "js/critical.js" => %{"file" => "assets/main.js", "name" => "main", "isEntry" => true}
    }

    assert Manifest.parse(manifest).critical == %{}
  end
end
