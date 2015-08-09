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

  defp script_tag(src) do
    {:safe, html} = content_tag :script, "", [type: "text/javascript", charset: "utf-8",
                                              src: Brando.get_helpers.static_path(Brando.get_endpoint, src)]
    html
  end
end