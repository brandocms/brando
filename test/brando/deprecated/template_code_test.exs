defmodule Brando.Deprecated.TemplateCodeTest do
  use ExUnit.Case, async: true

  alias Brando.Deprecated.TemplateCode

  defp code(text, mode \\ :heex),
    do: for({:code, code, _line} <- TemplateCode.segments(text, mode), do: String.trim(code))

  test "a script or style tag's attributes and EEx tags are code; a custom element is not a script" do
    assert code(~S|<script src={Upload.url(@x)} type="module"><%= Upload.y() %> {not_code}</script>|) ==
             ["Upload.url(@x)", "Upload.y()"]

    assert code(~S|<style nonce={n(@x)}>a { b: c }</style>|) == ["n(@x)"]
    assert code(~S|<style-box a={1}></style-box><p>{2}</p>|) == ["1", "2"]
  end

  test "EEx tags inside an HTML comment are code; a HEEx comment is not" do
    assert code(~S|<!-- <%= a() %> {b} --><%!-- <%= c() %> --%>|) == ["a()"]
    assert code(~S|<!-- <%= a() %> -->|, :eex) == ["a()"]
  end

  test "Surface blocks are code without their keyword" do
    assert code(~S|{#if x?(@a)}a{#elseif y}b{/if}{#for u <- list()}{u}{/for}|, :surface) ==
             ["x?(@a)", "y", "", "u <- list()", "u", ""]
  end

  test "an unclosed string or brace ends at the end of the text" do
    assert [{:code, _, 0}] = TemplateCode.segments(<<"{\"\\">>, :heex)
    assert [{:code, _, 0}] = TemplateCode.segments(<<"<p>{\"a\\">>, :heex)
  end
end
