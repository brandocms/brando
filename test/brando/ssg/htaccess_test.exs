defmodule Brando.SSG.HtaccessTest do
  use ExUnit.Case, async: true

  alias Brando.SSG.Htaccess

  @languages {["en", "no"], "en"}

  defp entry(fields) do
    Map.merge(
      %{"kind" => "rule", "source" => nil, "target" => "/to", "status" => 301, "exact" => true, "language" => nil},
      Map.new(fields, fn {key, value} -> {to_string(key), value} end)
    )
  end

  defp list(entries, extra \\ %{}), do: Map.merge(%{"version" => 1, "redirects" => entries}, extra)

  defp block(entries, opts \\ []) do
    Htaccess.block(
      list(entries, opts[:list] || %{}),
      opts[:languages] || @languages,
      Keyword.get(opts, :not_found_page, true),
      opts[:manifest_files] || []
    )
  end

  defp lines(block), do: String.split(block, "\n", trim: true)

  # The regular expression of the last condition before the redirect, read as
  # Elixir reads it: the same PCRE syntax Apache reads
  defp path_regex(block) do
    block
    |> lines()
    |> Enum.filter(&String.starts_with?(&1, "RewriteCond %{ENV:BRANDO_PATH} ^"))
    |> List.last()
    |> String.replace_prefix("RewriteCond %{ENV:BRANDO_PATH} ", "")
    |> Regex.compile!()
  end

  describe "block/4" do
    test "a list with no redirects is a block with the 404 page and the cache headers" do
      for list <- [nil, list([]), %{"version" => 1}] do
        assert {block, []} = Htaccess.block(list, @languages, true, [])

        assert lines(block) == [
                 "# BEGIN Brando",
                 "# Written by Brando at each deploy: what is between these two lines is replaced.",
                 "ErrorDocument 404 /404.html",
                 "<IfModule mod_headers.c>",
                 ~s[Header always set Cache-Control "no-cache"],
                 "</IfModule>",
                 "# END Brando"
               ]
      end
    end

    test "names no 404 page for a build without one" do
      assert {block, []} = block([], not_found_page: false)
      refute block =~ "ErrorDocument"
    end

    test "a listed exact redirect drops the request's query" do
      listed = entry(kind: "listed", source: "/old-about", target: "/about", pattern: "/old\\-about$")
      assert {block, []} = block([listed])

      assert block =~
               """
               RewriteCond %{ENV:BRANDO_PATH} ^/old-about$
               RewriteRule ^ /about? [R=301,NE,L]
               """

      refute block =~ "BRANDO_FILE"
    end

    test "the path is read without trailing slashes and with its case" do
      assert {block, []} = block([entry(source: "/old", pattern: "/old$")])
      assert block =~ "RewriteCond %{REQUEST_URI} (?s)^(/.*?)/*$\nRewriteRule ^ - [E=BRANDO_PATH:%1]\n"

      [_whole, path] = Regex.run(~r/^(\/.*?)\/*$/s, "/old//")
      assert Regex.match?(path_regex(block), path)
      refute Regex.match?(path_regex(block), "/Old")
      refute Regex.match?(path_regex(block), "/older")
    end

    test "a target with its own query keeps it" do
      assert {block, []} = block([entry(source: "/q", pattern: "/q$", target: "/about?from=q")])
      assert block =~ "RewriteRule ^ /about?from=q [R=301,NE,L]\n"
    end

    test "a rule with :name segments captures them for its target, and a built file wins over it" do
      rule =
        entry(
          source: "/news/:year/:slug",
          target: "/articles/:slug/:year/:other",
          pattern: "/news/:year/:slug",
          exact: false
        )

      assert {block, []} = block([rule])

      assert block =~
               """
               RewriteCond %{ENV:BRANDO_FILE} ^1$
               RewriteCond %{ENV:BRANDO_PATH} ^/news/([a-z0-9_-]+)/([a-z0-9_-]+)
               RewriteRule ^ - [L]
               RewriteCond %{ENV:BRANDO_PATH} ^/news/([a-z0-9_-]+)/([a-z0-9_-]+)
               RewriteRule ^ /articles/%2/%1/:other? [R=301,NE,L]
               """

      assert block =~
               """
               RewriteCond %{ENV:BRANDO_PATH} /[^/]+\\.[^/]*$
               RewriteCond %{DOCUMENT_ROOT}%{ENV:BRANDO_PATH} -f
               RewriteRule ^ - [E=BRANDO_FILE:1]
               RewriteCond %{ENV:BRANDO_PATH} !/[^/]+\\.[^/]*$
               RewriteCond %{DOCUMENT_ROOT}%{ENV:BRANDO_PATH}/index.html -f
               RewriteRule ^ - [E=BRANDO_FILE:1]
               """
    end

    test "the file's extension is read as Path.extname/1 reads it" do
      assert {block, []} = block([entry(source: "/a", pattern: "/a", exact: false)])
      [extension] = Regex.run(~r/BRANDO_PATH\} (\/\S+\$)\n/, block, capture: :all_but_first)
      extension = Regex.compile!(extension)

      for path <- ["/a/b.css", "/a/..b", "/a/b.", "/a/.b", "/a.b/c", "/"] do
        assert Regex.match?(extension, path) == (Path.extname(path) != ""), path
      end
    end

    test "a 410 is gone" do
      assert {block, []} = block([entry(source: "/gone", pattern: "/gone$", status: 410, target: nil)])
      assert block =~ "RewriteCond %{ENV:BRANDO_PATH} ^/gone$\nRewriteRule ^ - [G]\n"
    end

    test "a rule applies only to a request in its language" do
      rules = [
        entry(source: "/en", pattern: "/en$", language: "en"),
        entry(source: "/no", pattern: "/no$", language: "no"),
        entry(source: "/de", pattern: "/de$", language: "de")
      ]

      assert {block, []} = block(rules)

      assert block =~
               """
               RewriteCond %{ENV:BRANDO_PATH} !^/(?:no)(?:/|$)
               RewriteCond %{ENV:BRANDO_PATH} ^/en$
               """

      assert block =~
               """
               RewriteCond %{ENV:BRANDO_PATH} ^/no(?:/|$)
               RewriteCond %{ENV:BRANDO_PATH} ^/no$
               """

      refute block =~ "/de"
    end

    test "the list's languages, and the site's for a list without them" do
      rule = entry(source: "/x", pattern: "/x$", language: "sv")

      assert {block, []} = block([rule], list: %{"languages" => ["sv", "da"], "default_language" => "da"})
      assert block =~ "RewriteCond %{ENV:BRANDO_PATH} ^/sv(?:/|$)\n"

      assert {block, []} = block([rule], languages: {["sv"], "sv"})
      assert block =~ "RewriteCond %{ENV:BRANDO_PATH} ^/x$\nRewriteRule"

      assert {block, []} = block([rule])
      refute block =~ "/x"
    end

    test "entries LocalDelivery leaves out are left out" do
      entries = [
        entry(source: "/a", pattern: nil),
        entry(source: "/b", pattern: "/b(", target: "/x"),
        entry(source: "/c", pattern: "/c$", status: "301"),
        "/d"
      ]

      assert {block, []} = block(entries)
      refute block =~ "RewriteEngine"
    end

    test "a source is written byte for byte, whatever its characters" do
      source = "/a b$c%d#e\"f'g\\h\ni[j]ø"
      escaped = Brando.Sites.Redirects.exact_source(source)
      assert {block, []} = block([entry(source: source, pattern: escaped)])

      assert block =~
               "RewriteCond %{ENV:BRANDO_PATH} ^/a\\x20b\\x24c\\x25d\\x23e\\x22f\\x27g\\x5ch\\x0ai\\x5bj\\x5d\\xc3\\xb8$\n"

      assert Regex.match?(path_regex(block), source)
      refute Regex.match?(path_regex(block), String.replace(source, "ø", "o"))
    end

    test "a rule written as a regular expression counts the groups before its :name segment" do
      rule = entry(pattern: "/(blog|[(]journal)/(?:x)?(?<y>z)?/:slug", target: "/articles/:slug/:y", exact: false)
      assert {block, []} = block([rule])

      assert block =~
               "RewriteCond %{ENV:BRANDO_PATH} (?-s)^/(blog|[(]journal)/(?:x)?(?<y>z)?/(?<slug>[a-z0-9_-]+)\n" <>
                 "RewriteRule ^ /articles/%3/%2? [R=301,NE,L]\n"
    end

    test "a rule written as a regular expression whose groups cannot be counted is left out when its target names one" do
      rule = entry(pattern: "/\\Q(\\E/:slug", target: "/articles/:slug", exact: false)
      assert {block, [note]} = block([rule])
      assert note =~ "/\\\\Q(\\\\E/:slug"
      refute block =~ "RewriteEngine"

      assert {block, []} = block([%{rule | "target" => "/articles"}])
      assert block =~ "RewriteRule ^ /articles? [R=301,NE,L]\n"
    end

    test "a target naming a group after the ninth is left out" do
      pattern = "/" <> Enum.map_join(1..10, "/", &":s#{&1}")
      assert {block, [_note]} = block([entry(source: pattern, pattern: pattern, target: "/:s10", exact: false)])
      refute block =~ "RewriteEngine"

      assert {block, []} = block([entry(source: pattern, pattern: pattern, target: "/:s9", exact: false)])
      assert block =~ "RewriteRule ^ /%9? [R=301,NE,L]\n"
    end

    test "a regular expression .htaccess cannot hold as it is is left out" do
      for pattern <- ["/(a b)", "/(a#b)", "/(a\"b)", "/(a'b)", "/(a\tb)", "/(a)\\\\"] do
        assert {block, [note]} = block([entry(pattern: pattern)])
        assert note =~ "pattern"
        refute block =~ "RewriteEngine"
      end
    end

    test "nothing from a target ends a directive, adds a flag or reads as a backreference" do
      hostile = [
        "/x\nRewriteRule ^ http://evil.example/ [R=302,L]",
        "/x\r",
        "/x\0",
        "/x [R=302,E=HOME:/etc]",
        "/x\"y",
        "/x'y",
        "/x\\y",
        "/x/$1",
        "/x/%1",
        "/x/%{ENV:HOME}",
        "/x#frag",
        "/x{y}",
        "//evil.example/x",
        "relative/path",
        "javascript:alert(1)"
      ]

      entries = Enum.map(hostile, &entry(source: "/from", pattern: "/from$", target: &1))
      assert {block, notes} = block(entries)
      assert length(notes) == length(hostile)
      refute block =~ "RewriteEngine"

      for {note, target} <- Enum.zip(notes, hostile), do: assert(note =~ inspect(target))
    end

    test "spaces, bytes outside ASCII and % escapes are percent-encoded so Apache sends them as they are" do
      entries = [
        entry(source: "/a", pattern: "/a$", target: "/søk/a b?q=100%25&r=%e2"),
        entry(source: "/b", pattern: "/b$", target: "https://example.com/x?y=1")
      ]

      assert {block, []} = block(entries)
      assert block =~ "RewriteRule ^ /s\\%C3\\%B8k/a\\%20b?q=100\\%25&r=\\%e2 [R=301,NE,L]\n"
      assert block =~ "RewriteRule ^ https://example.com/x?y=1 [R=301,NE,L]\n"
    end

    test "a status that is no redirect, or a redirect without a target, is left out" do
      entries = [entry(source: "/a", pattern: "/a$", status: 200), entry(source: "/b", pattern: "/b$", target: nil)]
      assert {block, [_status, _target]} = block(entries)
      refute block =~ "RewriteEngine"
    end

    test "caches the manifest's files and their source maps for a year, pages excepted" do
      files = ["assets/app-1a2b.js", "assets/app-3c4d.css", "assets/app-1a2b.js", "index.html", "docs.md"]
      assert {block, []} = block([], manifest_files: files)

      assert block =~
               """
               <IfModule mod_headers.c>
               Header always set Cache-Control "no-cache"
               <FilesMatch "^(?:app-1a2b\\x2ejs|app-1a2b\\x2ejs\\x2emap|app-3c4d\\x2ecss|app-3c4d\\x2ecss\\x2emap)$">
               Header always set Cache-Control "public, max-age=31536000, immutable"
               </FilesMatch>
               </IfModule>
               """
    end
  end

  describe "merge/2" do
    @block "# BEGIN Brando\nErrorDocument 404 /404.html\n# END Brando\n"

    test "a target without a .htaccess gets the block alone" do
      assert Htaccess.merge(nil, @block) == {:ok, @block}
      assert Htaccess.merge("", @block) == {:ok, @block}
    end

    test "the block goes after the host's lines" do
      assert Htaccess.merge("Options -Indexes\n", @block) == {:ok, "Options -Indexes\n" <> @block}
      assert Htaccess.merge("Options -Indexes", @block) == {:ok, "Options -Indexes\n" <> @block}
    end

    test "replaces the block where it is, and keeps the lines after it" do
      current = "A\n# BEGIN Brando\nold\n# END Brando\nB\n"
      assert Htaccess.merge(current, @block) == {:ok, "A\n" <> @block <> "B\n"}
    end

    test "keeps CRLF lines byte for byte" do
      current = "A\r\n  # BEGIN Brando  \r\nold\r\n# END Brando\r\nB \r\nC"
      assert Htaccess.merge(current, @block) == {:ok, "A\r\n" <> @block <> "B \r\nC"}
    end

    test "a BEGIN without its END is refused" do
      assert Htaccess.merge("A\n# BEGIN Brando\nB\n", @block) == {:error, :unterminated_block}
      assert Htaccess.merge("# END Brando\n# BEGIN Brando\n", nil) == {:error, :unterminated_block}
    end

    test "an END without a BEGIN is a host line" do
      assert Htaccess.merge("# END Brando\n", @block) == {:ok, "# END Brando\n" <> @block}
    end

    test "every block is replaced by one" do
      current = "A\n# BEGIN Brando\n1\n# END Brando\nB\n# BEGIN Brando\n2\n# END Brando\nC\n"
      assert Htaccess.merge(current, @block) == {:ok, "A\n" <> @block <> "B\nC\n"}
    end

    test "without a block, removes the block and returns the rest, or says nothing is left" do
      assert Htaccess.merge("A\n# BEGIN Brando\nold\n# END Brando\nB", nil) == {:ok, "A\nB"}
      assert Htaccess.merge("A\n", nil) == {:ok, "A\n"}
      assert Htaccess.merge("\n# BEGIN Brando\nold\n# END Brando\n \n", nil) == :empty
      assert Htaccess.merge(nil, nil) == :empty
    end

    test "keeps bytes that are not UTF-8" do
      assert Htaccess.merge(<<"# caf", 0xE9, "\n">>, @block) == {:ok, <<"# caf", 0xE9, "\n">> <> @block}
    end
  end
end
