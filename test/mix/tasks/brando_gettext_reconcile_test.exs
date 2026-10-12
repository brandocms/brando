defmodule Mix.Tasks.Brando.Gettext.ReconcileTest do
  use ExUnit.Case, async: true

  alias Mix.Brando.GettextReconcile
  alias Mix.Tasks.Brando.Gettext.Reconcile

  @header """
  msgid ""
  msgstr ""
  "Language: no\\n"
  "Plural-Forms: nplurals=2; plural=(n != 1);\\n"
  """

  setup do
    root = Path.join(System.tmp_dir!(), "brando-gettext-reconcile-#{System.unique_integer([:positive])}")
    dir = Path.join(root, "priv/gettext/backend")
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, dir: dir}
  end

  defp write(dir, path, contents) do
    path = Path.join(dir, path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, contents)
  end

  defp message(msgid, msgstr \\ ""), do: ~s(\nmsgid "#{msgid}"\nmsgstr "#{msgstr}"\n)

  defp pot(messages), do: ~s(msgid ""\nmsgstr ""\n) <> Enum.map_join(messages, &message/1)

  defp po(header, messages), do: header <> Enum.map_join(messages, fn {id, str} -> message(id, str) end)

  defp translations(path) do
    for %Expo.Message.Singular{} = message <- Expo.PO.parse_file!(path).messages, into: %{} do
      {IO.iodata_to_binary(message.msgid), IO.iodata_to_binary(message.msgstr)}
    end
  end

  # A backend as `mix brando.migrate55` leaves it: the Blueprint's 0.53 forms
  # domain beside the per-schema domain it was copied into, a `default`
  # domain, and the locales `no` and `en`, where `en` never had the
  # per-schema catalog. The Blueprint's tab label "Content", now `t/1`, moved
  # from `default` to the Blueprint's domain.
  defp fixture(dir) do
    write(dir, "default.pot", pot(["Content", "Save"]))
    write(dir, "projects_project.pot", pot(["Delete project", "Title", "project"]))
    write(dir, "projects_project_forms.pot", pot(["Delete project", "Title"]))

    write(dir, "no/LC_MESSAGES/default.po", po(@header, [{"Content", "Innhold"}, {"Save", "Lagre"}]))

    write(
      dir,
      "no/LC_MESSAGES/projects_project.po",
      po(@header, [{"Delete project", "Slett prosjekt"}, {"Title", "Tittel"}, {"project", "prosjekt"}])
    )

    write(
      dir,
      "no/LC_MESSAGES/projects_project_forms.po",
      po(@header, [{"Delete project", "Slett prosjekt"}, {"Title", "Tittel"}])
    )

    en = String.replace(@header, "Language: no", "Language: en")
    write(dir, "en/LC_MESSAGES/default.po", po(en, [{"Content", ""}, {"Save", ""}]))
    write(dir, "en/LC_MESSAGES/projects_project_forms.po", po(en, [{"Delete project", ""}, {"Title", ""}]))

    # What the extractor composes now: `default` lost "Content", the
    # Blueprint's domain gained it and lost the 0.53 action label, and the
    # forms domain has nothing left.
    %{
      Path.join(dir, "default.pot") => pot(["Save"]),
      Path.join(dir, "projects_project.pot") => pot(["Content", "Title", "project"]),
      Path.join(dir, "projects_project_forms.pot") => pot([])
    }
  end

  test "merges the existing locales, fills from siblings, deletes the emptied 0.53 domain and reports", %{dir: dir} do
    pots = fixture(dir)

    report = GettextReconcile.reconcile(dir, pots, blueprint_domains: ["projects_project"])

    assert File.ls!(dir) |> Enum.sort() == ["default.pot", "en", "no", "projects_project.pot"]
    assert File.ls!(Path.join(dir, "no/LC_MESSAGES")) |> Enum.sort() == ["default.po", "projects_project.po"]
    assert File.ls!(Path.join(dir, "en/LC_MESSAGES")) |> Enum.sort() == ["default.po", "projects_project.po"]

    assert File.read!(Path.join(dir, "projects_project.pot")) == pots[Path.join(dir, "projects_project.pot")]
    assert translations(Path.join(dir, "no/LC_MESSAGES/default.po")) == %{"Save" => "Lagre"}

    assert translations(Path.join(dir, "no/LC_MESSAGES/projects_project.po")) == %{
             "Content" => "Innhold",
             "Title" => "Tittel",
             "project" => "prosjekt"
           }

    # A catalog the locale never had is created with its header.
    en = File.read!(Path.join(dir, "en/LC_MESSAGES/projects_project.po"))
    assert en =~ ~S|"Language: en\n"|
    assert en =~ ~S|"Plural-Forms: nplurals=2; plural=(n != 1);\n"|

    assert translations(Path.join(dir, "en/LC_MESSAGES/projects_project.po")) == %{
             "Content" => "",
             "Title" => "",
             "project" => ""
           }

    assert Enum.sort(report.deleted) ==
             Enum.sort([
               Path.join(dir, "projects_project_forms.pot"),
               Path.join(dir, "en/LC_MESSAGES/projects_project_forms.po"),
               Path.join(dir, "no/LC_MESSAGES/projects_project_forms.po")
             ])

    assert [
             %{domain: "projects_project", locale: "en", carried: 0, filled: [], dropped: [], untranslated: 3},
             %{
               domain: "projects_project",
               locale: "no",
               carried: 2,
               filled: ["Content"],
               dropped: ["Delete project"],
               untranslated: 0
             }
           ] = report.domains

    text = Reconcile.report([report], false)
    assert text =~ "==> #{dir}"
    assert text =~ "Deleted 3: "

    assert text =~
             ~s{  projects_project (no): 2 carried, 1 filled from a sibling, 1 dropped, 0 untranslated\n} <>
               ~s{      dropped, no longer in the source: "Delete project"}

    # Running it again changes nothing.
    again = GettextReconcile.reconcile(dir, pots, blueprint_domains: ["projects_project"])
    assert {again.written, again.deleted} == {[], []}
  end

  test "--dry-run reports the same and writes nothing", %{dir: dir} do
    pots = fixture(dir)
    before = for path <- Path.wildcard(Path.join(dir, "**/*.{po,pot}")), into: %{}, do: {path, File.read!(path)}

    report = GettextReconcile.reconcile(dir, pots, dry_run: true, blueprint_domains: ["projects_project"])

    assert for(path <- Path.wildcard(Path.join(dir, "**/*.{po,pot}")), into: %{}, do: {path, File.read!(path)}) == before
    assert length(report.deleted) == 3
    assert [_en, %{locale: "no", filled: ["Content"], dropped: ["Delete project"]}] = report.domains
    assert Reconcile.report([report], true) =~ "Would delete 3: "
  end

  test "a 0.53 domain the source still uses is kept", %{dir: dir} do
    pots = fixture(dir)
    pots = Map.put(pots, Path.join(dir, "projects_project_forms.pot"), pot(["Title"]))

    report = GettextReconcile.reconcile(dir, pots, blueprint_domains: ["projects_project"])

    assert report.deleted == []
    assert translations(Path.join(dir, "no/LC_MESSAGES/projects_project_forms.po")) == %{"Title" => "Tittel"}
  end

  test "an unknown option stops the task" do
    assert_raise Mix.Error, ~r/mix brando.gettext.reconcile: unknown or invalid option --merge/, fn ->
      Reconcile.run(["--merge"])
    end
  end
end
