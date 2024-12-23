defmodule Brando.Assets.Vite do
  defmodule ViteManifestReader do
    @moduledoc """
    Finding proper path for `cache_manifest.json` in releases is a non-trivial operation,
    so we keep this logic in a dedicated module with some logic copied verbatim from
    a Phoenix private function from Phoenix.Endpoint.Supervisor
    """

    require Logger

    def read(manifest_file, cache_key) do
      case :persistent_term.get(cache_key, nil) do
        nil ->
          hmr? = Application.get_env(Brando.otp_app(), :hmr, false)
          res = do_read(manifest_file, hmr?)
          :persistent_term.put(cache_key, res)
          res

        res ->
          res
      end
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
        outer |> File.read!() |> Jason.decode!()
      else
        Logger.error("Could not find vite manifest at #{inspect(outer)}.")
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

    def config(:app) do
      %{
        manifest_file: "priv/static/manifest.json",
        manifest_cache_key: {:vite, "cache_manifest"},
        entry_file: "js/index.js",
        legacy_entry: "js/index-legacy.js",
        legacy_polyfills: "vite/legacy-polyfills",
        critical_css_file: "js/critical.js",
        critical_css_cache_key: {:vite, "critical_css"}
      }
    end

    def config(:admin) do
      %{
        manifest_file: "priv/static/admin_manifest.json",
        manifest_cache_key: {:vite, "cache_admin_manifest"},
        entry_file: "src/main.js"
      }
    end

    @spec read(atom) :: map()
    def read(scope) do
      scope
      |> config
      |> Map.get(:manifest_file)
      |> ViteManifestReader.read(config(scope).manifest_cache_key)
    end

    @spec main_js(atom) :: binary()
    def main_js(scope) do
      get_file(scope, config(scope).entry_file)
    end

    @spec legacy_entry(atom) :: binary()
    def legacy_entry(scope) do
      get_file(scope, config(scope).legacy_entry)
    end

    @spec legacy_polyfills(atom) :: binary()
    def legacy_polyfills(scope) do
      get_file(scope, config(scope).legacy_polyfills)
    end

    @spec main_css(atom) :: binary()
    def main_css(scope) do
      get_css(scope, config(scope).entry_file)
    end

    def critical_css(scope \\ :app) do
      case :persistent_term.get(config(scope).critical_css_cache_key, nil) do
        nil ->
          critical_css_file = get_in(read(scope), [config(scope).critical_css_file, "css"])

          res =
            if critical_css_file do
              Brando.env()
              |> critical_css(critical_css_file)
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

    def critical_css(:prod, critical_css_file) do
      outer =
        Application.app_dir(
          Brando.endpoint().config(:otp_app),
          Path.join("priv/static", critical_css_file)
        )

      if File.exists?(outer) do
        File.read!(outer)
      else
        "/* no critical css */"
      end
    end

    def critical_css(_, critical_css_file) do
      outer = Path.join("priv/static", critical_css_file)

      if File.exists?(outer) do
        File.read!(outer)
      else
        "/* no critical css */"
      end
    end

    @spec vendor_js(atom) :: binary()
    def vendor_js(scope) do
      scope
      |> get_imports(config(scope).entry_file)
      |> Enum.at(0)
    end

    @spec get_file(atom, binary()) :: binary()
    def get_file(scope, file) do
      read(scope) |> get_in([file, "file"]) |> prepend_slash()
    end

    @spec get_css(:admin | :app, binary()) :: binary()
    def get_css(scope, file) do
      read(scope) |> get_in([file, "css"]) |> prepend_slash()
    end

    @spec get_imports(atom, binary()) :: list(binary())
    def get_imports(scope, file) do
      imports = get_in(read(scope), [file, "imports"]) || []
      Enum.map(imports, fn import_file -> get_file(scope, import_file) end)
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
    alias Brando.Assets.Vite

    def static_path(file), do: Brando.helpers().static_path(Brando.endpoint(), file)

    def main_css(scope \\ :app) do
      case Vite.Manifest.main_css(scope) do
        nil ->
          ""

        css_files ->
          for css_file <- css_files do
            digested_css_file = static_path(css_file)
            "    <link phx-track-static rel=\"stylesheet\" href=\"#{digested_css_file}\">"
          end
      end
    end

    def main_js(scope \\ :app, ignored_chunks \\ []) do
      js_file = Vite.Manifest.main_js(scope)
      vendor_file = Vite.Manifest.vendor_js(scope)

      vendor_file =
        if vendor_file && String.starts_with?(vendor_file, ignored_chunks) do
          nil
        else
          vendor_file
        end

      digested_script =
        if js_file do
          digested_js_file = static_path(js_file)

          "<script type=\"module\" crossorigin defer phx-track-static src=\"#{digested_js_file}\"></script>"
        else
          ""
        end

      digested_vendor =
        if vendor_file do
          digested_vendor_file = static_path(vendor_file)
          "<link rel=\"modulepreload\" phx-track-static href=\"#{digested_vendor_file}\">"
        else
          ""
        end

      [digested_script, digested_vendor]
    end

    def legacy_js(scope \\ :app) do
      legacy_entry = Vite.Manifest.legacy_entry(scope)
      legacy_polyfills = Vite.Manifest.legacy_polyfills(scope)

      digested_legacy_polyfills =
        if legacy_polyfills do
          digested_polyfills = static_path(legacy_polyfills)

          "<script nomodule phx-track-static src=\"#{digested_polyfills}\"></script>"
        else
          ""
        end

      digested_entry_script =
        if legacy_entry do
          digested_entry = static_path(legacy_entry)

          "<script nomodule phx-track-static id=\"vite-legacy-entry\" data-src=\"#{digested_entry}\">System.import(document.getElementById('vite-legacy-entry').getAttribute('data-src'))</script>"
        else
          ""
        end

      helper =
        "<script nomodule>!function(){var e=document,t=e.createElement(\"script\");if(!(\"noModule\" in t)&&\"onbeforeload\" in t){var n=!1;e.addEventListener(\"beforeload\",(function(e){if(e.target===t)n=!0;else if(!e.target.hasAttribute(\"nomodule\")||!n)return;e.preventDefault()}),!0),t.type=\"module\",t.src=\".\",e.head.appendChild(t),t.remove()}}();</script>"

      [helper, digested_legacy_polyfills, digested_entry_script]
    end
  end
end
