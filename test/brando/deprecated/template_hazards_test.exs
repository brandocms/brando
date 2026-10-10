defmodule Brando.Deprecated.TemplateHazardsTest do
  use ExUnit.Case, async: true

  alias Brando.Deprecated.TemplateHazards

  defp uses?(text, token \\ "Upload"), do: TemplateHazards.uses([{"t.html.heex", 1, text}], token) != []

  test "a name code could continue is a use" do
    for text <- [
          "{Upload.url(@x)}",
          "{Upload\n  .url(@x)}",
          "{Upload}",
          "<.c ms={[Upload ]} />",
          "<.c ms={{Upload , 1}} />",
          "<p :if={Upload == @m}>",
          "<p :if={Upload in @ms}>",
          "{Upload |> to_string()}",
          "<%= case @m do %><% Upload -> %>a<% end %>",
          "<%= if match?(%Upload{}, @x) do %>",
          "<%= inspect Upload %>",
          "{case @x do\n  :a -> Upload\nend}",
          "{if @a do\n  Upload\nelse\n  nil\nend}",
          "{Enum.map(@xs, fn _ -> Upload end)}",
          "<%= try do\n  Upload\nrescue\n  _ -> 1\nend %>",
          "<%\n  mod = Upload\n  url = mod.url(@x)\n%>",
          "{Upload != @x}",
          "{Upload!=@x}",
          "{@m !== Upload or 1}",
          "<%= Upload # the store\n%>",
          "{Upload; 1}",
          "{Upload ^^^ 1}",
          "{Upload \\\\ 1}",
          "{!Upload}",
          ~S|{"#{Upload.url(@x)}"}|,
          "<p class=\"a{\">{Upload}</p>"
        ] do
      assert uses?(text), text
    end

    # .html.exs templates are code throughout
    for text <- ["div do\n  Upload\nend\n", "Upload.url(assigns.x)\n", "inspect(Upload)\n", "Upload"] do
      assert TemplateHazards.uses([{"t.html.exs", 1, text}], "Upload") != [], text
    end

    # A template the scan cannot follow is all code
    assert uses?("<p>{Upload a file</p>")

    for text <- ["<Meta.HTML.render_meta conn={@conn} />", "{Meta . HTML.x()}", "{Meta.\nHTML.x()}"] do
      assert uses?(text, "Meta.HTML"), text
    end
  end

  test "prose, strings, element text and other names are not" do
    for text <- [
          "<p>Upload a file</p>",
          "<span>Upload</span>",
          "Upload\n  <% :vimeo -> %>",
          ~S|{gettext("Upload")}|,
          ~S|{ngettext("Upload %{count} file", "Upload %{count} files", @n)}|,
          "<p>Upload Files</p>",
          "Uploads",
          "{Brando.Upload.x()}",
          "<.icon name=\"upload\" />",
          "<p>Upload! Upload? Upload;</p>",
          "<p title=\"Upload {x}\">Upload, Upload.</p>",
          "<%!-- Upload.x --%><!-- Upload.y -->",
          "<%= if @a do %>\n  Upload\n<% end %>"
        ] do
      refute uses?(text), text
    end
  end

  test "template files: template extensions, and .exs only with a format" do
    assert TemplateHazards.template_file?("lib/x/page.html.heex")
    assert TemplateHazards.template_file?("lib/x/page.html.exs")
    assert TemplateHazards.template_file?("priv/templates/x.sface")
    refute TemplateHazards.template_file?("test/x_test.exs")
    refute TemplateHazards.template_file?("config/dev.exs")
    refute TemplateHazards.template_file?("test/mix/brando.gen.blueprint_migration_test.exs")
    refute TemplateHazards.template_file?("lib/x/page.ex")
  end
end
