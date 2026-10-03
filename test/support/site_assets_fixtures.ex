defmodule Brando.SiteAssetsFixtures do
  @moduledoc false

  alias Brando.Assets.SiteAssets
  alias Brando.Tenant.Registry

  @doc "Writes a one-entry Vite build named `name` under the site's asset sets root and returns its path."
  def create_set(site, name, js_content, css_file) do
    path = Path.join(SiteAssets.sets_root(site), name)
    File.mkdir_p!(Path.join(path, "assets"))
    File.write!(Path.join([path, "assets", "#{name}.js"]), js_content)
    File.write!(Path.join([path, "assets", css_file]), "body{}")

    manifest = %{
      "src/main.js" => %{"isEntry" => true, "file" => "assets/#{name}.js", "css" => ["assets/#{css_file}"]}
    }

    File.write!(Path.join(path, "manifest.json"), Jason.encode!(manifest))
    path
  end

  @doc "Creates an active dynamic site with a live production environment on `domain`."
  def create_site(name, key, domain) do
    {:ok, site} =
      Registry.create_site(%{
        name: name,
        key: key,
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :dynamic
      })

    {:ok, _environment} =
      Registry.create_environment(site, %{name: "Production", key: "production", live: true, domain: domain})

    {:ok, Registry.get_site(site.id)}
  end
end
