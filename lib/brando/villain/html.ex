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
    extra_blocks = Keyword.get(Brando.config(Brando.Villain), :extra_blocks, [])

    extras =
      for extra <- extra_blocks do
        script_tag("/js/blocks.#{String.downcase(extra)}.js")
      end

    [script_tag("/js/villain.all.js") | extras] |> raw
  end

  @doc """
  Renders javascript initialization for Villain.

  ## Options

    * `browse_url`: url to image browser
    * `upload_url`: url for image POST'ing
    * `source`: selector for the textarea source

  """
  def initialize(opts) do
    base_url = Keyword.fetch!(opts, :base_url)
    image_series = Keyword.fetch!(opts, :image_series)
    source = Keyword.fetch!(opts, :source)
    default_blocks = Keyword.get(opts, :default_blocks, [])
    extra_blocks = Keyword.get(Brando.config(Brando.Villain), :extra_blocks, [])

    extra_blocks =
      if extra_blocks == [] do
        "// extraBlocks: []"
      else
        "extraBlocks: #{inspect(extra_blocks)}"
      end

    default_blocks =
      if default_blocks == [] do
        "// defaultBlocks: []"
      else
        "defaultBlocks: #{build_default_blocks(default_blocks)}"
      end

    html = """
    <script type="text/javascript">
      document.addEventListener('DOMContentLoaded', function() {
        v = new Villain.Editor({
          #{extra_blocks},
          #{default_blocks},
          baseURL: '#{base_url}',
          imageSeries: '#{image_series}',
          textArea: '#{source}'
        });
      });
    </script>
    """

    raw(html)
  end

  defp script_tag(src) do
    {:safe, html} =
      content_tag(:script, "",
        charset: "utf-8",
        type: "text/javascript",
        src: Brando.helpers().static_path(Brando.endpoint(), src)
      )

    html
  end

  defp build_default_blocks(block_list) do
    l =
      Enum.map(block_list, fn {block_name, block_cls} ->
        ~s({name: '#{block_name}', cls: #{block_cls}})
      end)
      |> Enum.join(", ")

    "[#{l}]"
  end
end
