defmodule Brando.Markdown do
  @moduledoc """
  Converts Markdown to HTML.

  Markdown content is authored by trusted CMS editors, so raw HTML and links are
  preserved to remain compatible with Brando's previous Earmark rendering.
  """

  @mdex_options [
    extension: [autolink: true, strikethrough: true, table: true],
    parse: [smart: true],
    render: [unsafe: true]
  ]

  @type option :: {:breaks, boolean()}
  @type options :: [option()]

  @doc """
  Converts Markdown to HTML.

  Set `:breaks` to `true` to render soft line breaks as `<br />` elements.
  """
  @spec to_html(String.t(), options()) :: {:ok, String.t()} | {:error, term()}
  def to_html(markdown, opts \\ []) when is_binary(markdown) do
    MDEx.to_html(markdown, mdex_options(opts))
  end

  @doc """
  Converts Markdown to HTML, raising if conversion fails.

  Set `:breaks` to `true` to render soft line breaks as `<br />` elements.
  """
  @spec to_html!(String.t(), options()) :: String.t()
  def to_html!(markdown, opts \\ []) when is_binary(markdown) do
    MDEx.to_html!(markdown, mdex_options(opts))
  end

  defp mdex_options(opts) do
    opts = Keyword.validate!(opts, breaks: false)
    render_options = Keyword.put(@mdex_options[:render], :hardbreaks, opts[:breaks])
    Keyword.put(@mdex_options, :render, render_options)
  end
end
