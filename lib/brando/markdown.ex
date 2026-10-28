defmodule Brando.Markdown do
  @moduledoc """
  Converts Markdown to HTML.

  Markdown comes from editors, so its HTML is safe by default: raw HTML in it
  is left out (MDEx writes `<!-- raw HTML omitted -->` in its place), and so
  are the addresses of links and images with a script or other unsafe scheme
  (`javascript:`, `vbscript:`, `file:`, and `data:` other than images). Pass
  `safe: false` only for Markdown no editor wrote.
  """

  @mdex_options [
    extension: [autolink: true, strikethrough: true, table: true],
    parse: [smart: true],
    render: [unsafe: false]
  ]

  @type option :: {:breaks, boolean()} | {:safe, boolean()}
  @type options :: [option()]

  @doc """
  Converts Markdown to HTML.

  Set `:breaks` to `true` to render soft line breaks as `<br />` elements.
  `:safe` (default `true`) leaves out raw HTML and unsafe addresses.
  """
  @spec to_html(String.t(), options()) :: {:ok, String.t()} | {:error, term()}
  def to_html(markdown, opts \\ []) when is_binary(markdown) do
    MDEx.to_html(markdown, mdex_options(opts))
  end

  @doc """
  Converts Markdown to HTML, raising if conversion fails.

  Set `:breaks` to `true` to render soft line breaks as `<br />` elements.
  `:safe` (default `true`) leaves out raw HTML and unsafe addresses.
  """
  @spec to_html!(String.t(), options()) :: String.t()
  def to_html!(markdown, opts \\ []) when is_binary(markdown) do
    MDEx.to_html!(markdown, mdex_options(opts))
  end

  defp mdex_options(opts) do
    opts = Keyword.validate!(opts, breaks: false, safe: true)

    render_options =
      @mdex_options[:render]
      |> Keyword.put(:hardbreaks, opts[:breaks])
      |> Keyword.put(:unsafe, not opts[:safe])

    Keyword.put(@mdex_options, :render, render_options)
  end
end
