defmodule Brando.Villain.HTML do
  @moduledoc """
  HTML-helpers for Villain
  """
  import Phoenix.HTML.Tag, only: [content_tag: 3]
  import Phoenix.HTML, only: [raw: 1]

  @doc """
  Create includes needed for Villain.

  ## Example

  In your _scripts.new.html.eex:

      <%= Brando.Villain.HTML.include_scripts %>

  """
  def include_scripts do
    main = Mix.env == :dev && script_tag("/js/villain.all.js") || script_tag("/js/villain.all-min.js")
    extras = for extra <- Keyword.get(Brando.config(Brando.Villain), :extra_blocks, []) do
      script_tag("/js/blocks.#{String.downcase(extra)}.js")
    end
    [main|extras] |> raw
  end

  def initialize(opts) do
    browse_url   = Keyword.fetch!(opts, :browse_url)
    upload_url   = Keyword.fetch!(opts, :upload_url)
    source       = Keyword.fetch!(opts, :source)
    extra_blocks = Keyword.get(opts, :extra_blocks)

    extra_blocks =
      if extra_blocks do
        "extraBlocks: #{inspect(extra_blocks)}"
      else
        "// extraBlocks: []"
      end

    """
    <script type="text/javascript">
       $(document).ready(function() {
         v = new Villain.Editor({
           #{extra_blocks},
           browseURL: '#{browse_url}',
           uploadURL: '#{upload_url}',
           textArea: '#{source}'
         });
       });
    </script>
    """ |> raw
  end

  defp script_tag(src) do
    {:safe, html} = content_tag :script, "", [type: "text/javascript", charset: "utf-8",
                                              src: Brando.helpers.static_path(Brando.endpoint, src)]
    html
  end
end