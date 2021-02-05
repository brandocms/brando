defmodule Brando.Assets.Vite do
  defmodule ViteManifestReader do
    @moduledoc """
    Finding proper path for `cache_manifest.json` in releases is a non-trivial operation,
    so we keep this logic in a dedicated module with some logic copied verbatim from
    a Phoenix private function from Phoenix.Endpoint.Supervisor
    """

    require Logger

    @vite_manifest "priv/static/manifest.json"
    @cache_key {:vite, "cache_manifest"}

    def read() do
      case :persistent_term.get(@cache_key, nil) do
        nil ->
          res = read(Brando.env())
          :persistent_term.put(@cache_key, res)
          res

        res ->
          res
      end
    end

    @doc """
    # copy from
    - `defp cache_static_manifest(endpoint)`
    - https://github.com/phoenixframework/phoenix/blob/a206768ff4d02585cda81a2413e922e1dc19d556/lib/phoenix/endpoint/supervisor.ex#L411
    """
    def read(:prod) do
      outer = Application.app_dir(Brando.endpoint().config(:otp_app), @vite_manifest)

      if File.exists?(outer) do
        outer |> File.read!() |> Jason.decode!()
      else
        Logger.error(
          "Could not find static manifest at #{inspect(outer)}. " <>
            "Run \"mix phx.digest\" after building your static files " <>
            "or remove the configuration from \"config/prod.exs\"."
        )
      end
    end

    def read(_) do
      File.read!(@vite_manifest) |> Jason.decode!()
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
    # specified in vite.config.js in build.rollupOptions.input
    @entry_file "js/index.js"
    @legacy_entry "js/index-legacy.js"
    @legacy_polyfills "vite/legacy-polyfills"
    @critical_css_file "js/critical.js"
    @critical_css_cache_key {:vite, "critical_css"}

    @spec read() :: map()
    def read() do
      ViteManifestReader.read()
    end

    @spec main_js() :: binary()
    def main_js() do
      get_file(@entry_file)
    end

    @spec legacy_entry() :: binary()
    def legacy_entry() do
      get_file(@legacy_entry)
    end

    @spec legacy_polyfills() :: binary()
    def legacy_polyfills() do
      get_file(@legacy_polyfills)
    end

    @spec main_css() :: binary()
    def main_css() do
      get_css(@entry_file)
    end

    def critical_css do
      case :persistent_term.get(@critical_css_cache_key, nil) do
        nil ->
          critical_css_file = get_in(read(), [@critical_css_file, "css"])

          res =
            if critical_css_file do
              critical_css(Brando.env(), critical_css_file)
            else
              "/* no critical css */"
            end

          :persistent_term.put(@critical_css_cache_key, res)
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

    @spec vendor_js() :: binary()
    def vendor_js() do
      get_imports(@entry_file) |> Enum.at(0)
    end

    @spec get_file(binary()) :: binary()
    def get_file(file) do
      read() |> get_in([file, "file"]) |> prepend_slash()
    end

    @spec get_css(binary()) :: binary()
    def get_css(file) do
      read() |> get_in([file, "css"]) |> prepend_slash()
    end

    @spec get_imports(binary()) :: list(binary())
    def get_imports(file) do
      read() |> get_in([file, "imports"]) |> Enum.map(&get_file/1)
    end

    @spec prepend_slash(binary()) :: binary()
    defp prepend_slash(file) when is_binary(file) do
      "/" <> file
    end

    defp prepend_slash(file_list) when is_list(file_list) do
      Enum.map(file_list, &prepend_slash(&1))
    end
  end

  defmodule Render do
    import Phoenix.HTML
    alias Brando.Assets.Vite

    def static_path(file), do: Brando.helpers().static_path(Brando.endpoint(), file)

    def main_css do
      css_files = Vite.Manifest.main_css()

      for css_file <- css_files do
        digested_css_file = static_path(css_file)
        ~E|    <link phx-track-static rel="stylesheet" href="<%= digested_css_file %>">|
      end
    end

    def main_js do
      js_file = Vite.Manifest.main_js()
      vendor_file = Vite.Manifest.vendor_js()

      digested_js_file = static_path(js_file)
      digested_vendor_file = static_path(vendor_file)

      ~E|<script type="module" crossorigin defer phx-track-static src="<%= digested_js_file %>"></script>
    <link rel="modulepreload" href="<%= digested_vendor_file %>">
    |
    end

    def legacy_js do
      legacy_entry = Vite.Manifest.legacy_entry()
      legacy_polyfills = Vite.Manifest.legacy_polyfills()

      digested_entry = static_path(legacy_entry)
      digested_polyfills = static_path(legacy_polyfills)

      ~E[<script nomodule>!function(){var e=document,t=e.createElement("script");if(!("noModule"in t)&&"onbeforeload"in t){var n=!1;e.addEventListener("beforeload",(function(e){if(e.target===t)n=!0;else if(!e.target.hasAttribute("nomodule")||!n)return;e.preventDefault()}),!0),t.type="module",t.src=".",e.head.appendChild(t),t.remove()}}();</script>
      <script nomodule src="<%= digested_polyfills %>"></script>
      <script nomodule id="vite-legacy-entry" data-src="<%= digested_entry %>">System.import(document.getElementById('vite-legacy-entry').getAttribute('data-src'))</script>]
    end
  end
end
