defmodule E2E.StaticBuilder do
  @moduledoc """
  Builds a static site on the multi-site E2E server
  (`BRANDO_E2E_MULTI_SITE=1`, `config/e2e.exs`) without rendering it: the
  E2E project has no SSG module, and its sites have no pages to render. It
  writes one page, reporting it as `Brando.SSG.build/3` reports progress, so
  builds and deploys run their real course (`Brando.Worker.SSGBuild`).
  """

  def build(site, environment, opts) do
    output = Keyword.fetch!(opts, :output_path)
    progress = Keyword.get(opts, :progress, fn _event -> :ok end)
    page = "<!doctype html><title>#{site.name}</title><p>#{environment.name}</p>\n"

    progress.({:rendering, 1, 1, "/"})
    File.mkdir_p!(output)
    File.write!(Path.join(output, "index.html"), page)

    {:ok,
     %{file_count: 1, total_size: byte_size(page), url_count: 1, processed_urls: 1, failed_urls: []}}
  end
end
