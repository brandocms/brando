defmodule Brando.Assets.Vite do
  defmodule ViteManifestReader do
    @moduledoc """
    Finding proper path for `cache_manifest.json` in releases is a non-trivial operation,
    so we keep this logic in a dedicated module with some logic copied verbatim from
    a Phoenix private function from Phoenix.Endpoint.Supervisor
    """

    require Logger

    def read(manifest_file, cache_key, force \\ nil)

    def read(manifest_file, cache_key, nil) do
      case :persistent_term.get(cache_key, nil) do
        nil ->
          hmr? = Application.get_env(Brando.otp_app(), :hmr, false)
          res = do_read(manifest_file, hmr?)
          parsed_manifest = Brando.Assets.Vite.Manifest.parse(res)
          :persistent_term.put(cache_key, parsed_manifest)
          parsed_manifest

        res ->
          res
      end
    end

    def read(manifest_file, cache_key, :force) do
      hmr? = Application.get_env(Brando.otp_app(), :hmr, false)
      res = do_read(manifest_file, hmr?)
      parsed_manifest = Brando.Assets.Vite.Manifest.parse(res)
      :persistent_term.put(cache_key, parsed_manifest)
      parsed_manifest
    end

    @doc """
    # copy from
    - `defp cache_static_manifest(endpoint)`
    - https://github.com/phoenixframework/phoenix/blob/a206768ff4d02585cda81a2413e922e1dc19d556/lib/phoenix/endpoint/supervisor.ex#L411

    Read when HMR = true
    """
    def do_read(manifest_file, true) do
      case File.read(manifest_file) do
        {:error, :enoent} ->
          %{}

        {:ok, content} ->
          Jason.decode!(content)
      end
    end

    def do_read(manifest_file, false) do
      outer = Application.app_dir(Brando.endpoint().config(:otp_app), manifest_file)

      if File.exists?(outer) do
        outer
        |> File.read!()
        |> Jason.decode!()
      else
        if Application.get_env(:brando, :ssg_run) != :css do
          Logger.error("(!) Could not find vite manifest at #{inspect(outer)}.")
        end

        %{}
      end
    end
  end

  defmodule Manifest do
    @moduledoc """
    Basic and incomplete parser for Vite.js manifests
    See for more details:
    - https://vitejs.dev/guide/backend-integration.html
    - https://github.com/vitejs/vite/blob/main/packages/vite/src/node/plugins/manifest.ts
    Sample content for the manifest:
    `
    {
      "src/main.tsx": {
        "file": "assets/main.046c02cc.js",
        "src": "src/main.tsx",
        "isEntry": true,
        "imports": [
          "_vendor.ef08aed3.js"
        ],
        "css": "assets/main.54797e95.css"
      },
      "_vendor.ef08aed3.js": {
        "file": "assets/vendor.ef08aed3.js"
      }
    }
    `
    """
    @legacy_extension "-legacy"
    defstruct entries: %{}, critical: %{}, legacy: %{}

    def config(:app) do
      %{
        manifest_file: "priv/static/manifest.json",
        manifest_cache_key: {:vite, "cache_manifest"},
        critical_css_cache_key: {:vite, "critical_css"}
      }
    end

    def config(:admin) do
      %{
        manifest_file: "priv/static/admin_manifest.json",
        manifest_cache_key: {:vite, "cache_admin_manifest"}
      }
    end

    @spec read(atom) :: map()
    def read(scope) do
      scope
      |> config
      |> Map.get(:manifest_file)
      |> ViteManifestReader.read(config(scope).manifest_cache_key)
    end

    @spec refresh(atom) :: map()
    def refresh(scope) do
      scope
      |> config
      |> Map.get(:manifest_file)
      |> ViteManifestReader.read(config(scope).manifest_cache_key, :force)
    end

    defp add_css(manifest, css_files, type) do
      update_in(manifest, [Access.key(type), Access.key(:css_files, [])], fn cf ->
        cf ++ prepend_slash(css_files)
      end)
    end

    defp add_js(manifest, file, type) do
      type = (String.contains?(file, [@legacy_extension]) && :legacy) || type

      update_in(manifest, [Access.key(type), Access.key(:files, [])], fn files ->
        files ++ [prepend_slash(file)]
      end)
    end

    @doc """
    Parses the Vite manifest for a given scope and separates assets into entries, critical, and legacy.
    Takes a manifest scope (`:app` or `:admin`) and returns a struct containing parsed entries.

    Entry files with `critical` name are added to the :critical key, while regular entry files
    are added to :entries. CSS files are added under :css_files and JS files under :files.
    """
    def parse(manifest) do
      Enum.reduce(manifest, %__MODULE__{}, fn
        {_, %{"isEntry" => true, "name" => "critical", "file" => file, "css" => css_files}},
        acc ->
          acc
          |> add_css(css_files, :critical)
          |> add_js(file, :critical)

        {_, %{"isEntry" => true, "name" => "critical", "file" => file}}, acc ->
          add_js(acc, file, :critical)

        {_file, %{"isEntry" => true, "css" => css_files, "file" => file}}, acc ->
          acc
          |> add_css(css_files, :entries)
          |> add_js(file, :entries)

        {_file, %{"isEntry" => true, "file" => file}}, acc ->
          add_js(acc, file, :entries)

        _, acc ->
          acc
      end)
    end

    def critical_css(scope \\ :app) do
      case :persistent_term.get(config(scope).critical_css_cache_key, nil) do
        nil ->
          manifest = Manifest.read(scope)

          critical_css_files =
            get_in(manifest, [Access.key(:critical), Access.key(:css_files, [])])

          res =
            if critical_css_files != [] do
              Brando.env()
              |> critical_css(critical_css_files)
              |> Phoenix.HTML.raw()
            else
              "/* no critical css */"
            end

          :persistent_term.put(config(scope).critical_css_cache_key, res)
          res

        res ->
          res
      end
    end

    def critical_css(:prod, []) do
      "/* no critical css */"
    end

    def critical_css(:prod, critical_css_files) do
      Enum.reduce(critical_css_files, "", fn file, acc ->
        full_path =
          Application.app_dir(
            Brando.endpoint().config(:otp_app),
            Path.join("priv/static", file)
          )

        if File.exists?(full_path) do
          acc <> File.read!(full_path)
        else
          ""
        end
      end)
    end

    def critical_css(_, []) do
      "/* no critical css */"
    end

    def critical_css(_, critical_css_files) do
      Enum.reduce(critical_css_files, "", fn file, acc ->
        full_path = Path.join("priv/static", file)

        if File.exists?(full_path) do
          acc <> File.read!(full_path)
        else
          ""
        end
      end)
    end

    @spec prepend_slash(binary()) :: binary()
    defp prepend_slash(file) when is_binary(file) do
      "/" <> file
    end

    defp prepend_slash(file_list) when is_list(file_list) do
      Enum.map(file_list, &prepend_slash(&1))
    end

    defp prepend_slash(_) do
      nil
    end
  end

  defmodule Render do
    alias Brando.Assets.Vite.Manifest
    def static_path(file), do: Brando.helpers().static_path(Brando.endpoint(), file)

    def main_css(scope \\ :app) do
      manifest = Manifest.read(scope)

      css_entries = Brando.Utils.try_path(manifest, [:entries, :css_files]) || []

      for css_file <- css_entries do
        digested_css_file = static_path(css_file)
        "    <link phx-track-static rel=\"stylesheet\" href=\"#{digested_css_file}\">"
      end
    end

    def main_js(scope \\ :app, _vendored_scripts \\ []) do
      manifest = Manifest.read(scope)

      js_files = Brando.Utils.try_path(manifest, [:entries, :files]) || []

      digested_scripts =
        js_files
        |> Enum.reduce([], fn file, acc ->
          digested_file = static_path(file)

          acc ++
            [
              "<script type=\"module\" crossorigin defer phx-track-static src=\"#{digested_file}\"></script>"
            ]
        end)
        |> Enum.join("\n")

      # digested_vendor =
      #   if vendor_file do
      #     digested_vendor_file = static_path(vendor_file)
      #     "<link rel=\"modulepreload\" phx-track-static href=\"#{digested_vendor_file}\">"
      #   else
      #     ""
      #   end

      [digested_scripts]
    end

    def legacy_js(scope \\ :app) do
      manifest = Manifest.read(scope)
      legacy_files = Brando.Utils.try_path(manifest, [:legacy, :files]) || []

      digested_legacy_files =
        if legacy_files != [] do
          Enum.reduce(Enum.with_index(legacy_files), [], fn {file, idx}, acc ->
            digested_entry = static_path(file)

            acc ++
              [
                "<script nomodule phx-track-static id=\"vite-legacy-entry-#{idx}\" data-src=\"#{digested_entry}\">System.import(document.getElementById('vite-legacy-entry-#{idx}').getAttribute('data-src'))</script>"
              ]
          end)
        else
          []
        end

      helper =
        "<script nomodule>!function(){var e=document,t=e.createElement(\"script\");if(!(\"noModule\" in t)&&\"onbeforeload\" in t){var n=!1;e.addEventListener(\"beforeload\",(function(e){if(e.target===t)n=!0;else if(!e.target.hasAttribute(\"nomodule\")||!n)return;e.preventDefault()}),!0),t.type=\"module\",t.src=\".\",e.head.appendChild(t),t.remove()}}();</script>"

      [helper, Enum.join(digested_legacy_files, "\n")]
    end
  end
end
