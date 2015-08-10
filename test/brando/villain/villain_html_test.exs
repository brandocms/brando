defmodule Brando.Villain.HTMLTest do
  use ExUnit.Case, async: true

  test "include_scripts" do
    assert Brando.Villain.HTML.include_scripts
           == {:safe, [["<script charset=\"utf-8\" src=\"/js/villain.all-min.js\" type=\"text/javascript\">", "", "</script>"]]}

    add_extra_blocks()
    assert Brando.Villain.HTML.include_scripts
           == {:safe, [["<script charset=\"utf-8\" src=\"/js/villain.all-min.js\" type=\"text/javascript\">", "", "</script>"],
                       ["<script charset=\"utf-8\" src=\"/js/blocks.test1.js\" type=\"text/javascript\">", "", "</script>"],
                       ["<script charset=\"utf-8\" src=\"/js/blocks.test2.js\" type=\"text/javascript\">", "", "</script>"]]}
    remove_extra_blocks()
  end

  test "initialize" do
    assert Brando.Villain.HTML.initialize(browse_url: "/admin/pages/villain/browse/page",
                                          upload_url: "/admin/pages/villain/upload/page",
                                          source:     "textarea[name=\"page[data]\"]")
           == {:safe, "<script type=\"text/javascript\">\n   $(document).ready(function() {\n     v = new Villain.Editor({\n       // extraBlocks: [],\n       browseURL: '/admin/pages/villain/browse/page',\n       uploadURL: '/admin/pages/villain/upload/page',\n       textArea: 'textarea[name=\"page[data]\"]'\n     });\n   });\n</script>\n"}

    add_extra_blocks()
    assert Brando.Villain.HTML.initialize(browse_url: "/admin/pages/villain/browse/page",
                                          upload_url: "/admin/pages/villain/upload/page",
                                          source:     "textarea[name=\"page[data]\"]")
           == {:safe, "<script type=\"text/javascript\">\n   $(document).ready(function() {\n     v = new Villain.Editor({\n       extraBlocks: [\"Test1\", \"Test2\"],\n       browseURL: '/admin/pages/villain/browse/page',\n       uploadURL: '/admin/pages/villain/upload/page',\n       textArea: 'textarea[name=\"page[data]\"]'\n     });\n   });\n</script>\n"}
    remove_extra_blocks()
  end

  defp add_extra_blocks do
    cfg =
      Application.get_env(:brando, Brando.Villain)
      |> Keyword.put(:extra_blocks, ["Test1", "Test2"])
    Application.put_env(:brando, Brando.Villain, cfg)
  end

  defp remove_extra_blocks do
    cfg =
      Application.get_env(:brando, Brando.Villain)
      |> Keyword.put(:extra_blocks, [])
    Application.put_env(:brando, Brando.Villain, cfg)
  end
end