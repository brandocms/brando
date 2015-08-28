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

  @doc """
  Renders javascript initialization for Villain.

  ## Options

    * `browse_url`: url to image browser
    * `upload_url`: url for image POST'ing
    * `source`: selector for the textarea source

  """
  def initialize(opts) do
    base_url        = Keyword.fetch!(opts, :base_url)
    image_series    = Keyword.fetch!(opts, :image_series)
    source          = Keyword.fetch!(opts, :source)
    extra_blocks    = Keyword.get(Brando.config(Brando.Villain),
                                  :extra_blocks, [])

    extra_blocks =
      extra_blocks == [] && "// extraBlocks: []"
                         || "extraBlocks: #{inspect(extra_blocks)}"

    """
    <script type="text/javascript">
       $(document).ready(function() {
         v = new Villain.Editor({
           #{extra_blocks},
           baseURL: '#{base_url}',
           imageSeries: '#{image_series}',
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