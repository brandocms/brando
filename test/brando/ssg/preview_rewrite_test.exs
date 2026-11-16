defmodule Brando.SSG.PreviewRewriteTest do
  use ExUnit.Case, async: true

  alias Brando.SSG.PreviewRewrite

  @prefix "/__ssg_preview__/token"

  test "a srcset keeps its data: candidates whole, commas and all" do
    html = ~s(<img srcset="data:image/jpeg;base64,/9j/4AAQ 1x, /media/a.jpg 2x, data:image/png;base64,iVBO,/x">)

    assert PreviewRewrite.html(html, @prefix, ["https://example.com"]) ==
             ~s(<img srcset="data:image/jpeg;base64,/9j/4AAQ 1x, #{@prefix}/media/a.jpg 2x, data:image/png;base64,iVBO,/x">)
  end

  test "a srcset's candidates are rewritten with their descriptors" do
    html = ~s(<img data-srcset="/media/a.jpg 400w,https://example.com/media/b.jpg 800w">)

    assert PreviewRewrite.html(html, @prefix, ["https://example.com"]) ==
             ~s(<img data-srcset="#{@prefix}/media/a.jpg 400w,#{@prefix}/media/b.jpg 800w">)
  end
end
