defmodule Mix.Tasks.Brando.Migrate55BlueprintFixesTest do
  use ExUnit.Case, async: false

  import Igniter.Test

  alias Mix.Tasks.Brando.Migrate55

  @formatter """
  [
    inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
    locals_without_parens: [
      trait: 1, identifier: 1, data_layer: 1, attribute: 2, attribute: 3, relation: 2, relation: 3, asset: 3, input: 3
    ]
  ]
  """

  @property_path "lib/koi/projects/project/property.ex"
  @partner_path "lib/koi/team/partner.ex"
  @project_path "lib/koi/projects/project.ex"
  @controller_path "lib/koi_web/controllers/project_controller.ex"

  # As koi had them on 0.53.
  @property """
  defmodule Koi.Projects.Project.Property do
    @moduledoc \"""
    Blueprint for Project Property
    \"""
    use Brando.Blueprint,
      application: "Koi",
      domain: "Projects",
      schema: "Property",
      singular: "property",
      plural: "properties"

    data_layer :embedded
    identifier "{{ entry.id }}"

    attributes do
      attribute :key, :text, required: true
      attribute :value, :text, required: true
    end
  end
  """

  @partner """
  defmodule Koi.Team.Partner do
    use Brando.Blueprint,
      application: "Koi",
      domain: "Team",
      schema: "Partner",
      singular: "partner",
      plural: "partners"

    identifier "{{ entry.name }}"

    @logo_cfg [
      allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
      default_size: "xlarge",
      upload_path: Path.join(["images", "team", "partner"]),
      sizes: %{
        "small" => %{"quality" => 85, "size" => "700"},
        "xlarge" => %{"quality" => 85, "size" => "1900"}
      },
      default_srcset: [
        {"small", "700w"},
        {"xlarge", "1900w"}
      ]
    ]

    attributes do
      attribute :name, :string, required: true
    end

    assets do
      asset :logo, :image, cfg: @logo_cfg
    end
  end
  """

  @project """
  defmodule Koi.Projects.Project do
    use Brando.Blueprint,
      application: "Koi",
      domain: "Projects",
      schema: "Project",
      singular: "project",
      plural: "projects"

    identifier "{{ entry.title }}"

    attributes do
      attribute :title, :text, required: true
    end

    relations do
      relation :related_entries, :entries, constraints: [max_length: 3]
    end
  end
  """

  @controller """
  defmodule KoiWeb.ProjectController do
    use KoiWeb, :controller
    alias Koi.Projects

    def get_related_projects(project) do
      ids = Enum.map(project.related_entries || [], & &1.entry_id)

      Projects.list_projects(%{filter: %{ids: ids}, status: :published})
    end

    def related_titles(project) do
      Enum.map(project.related_entries, & &1.identifier.title)
    end
  end
  """

  test "turns off the identifier of an embedded Blueprint, and says so" do
    igniter = migrate(%{@property_path => @property})
    property = source(igniter, @property_path)

    assert property =~ "data_layer :embedded\n  identifier false\n"
    refute property =~ "entry.id"
    assert_has_notice(igniter, &(&1 =~ "#{@property_path}:13: `identifier false`"))

    rerun = igniter |> apply_igniter!() |> include_test_files() |> Migrate55.igniter()
    assert_unchanged(rerun, @property_path)
  end

  test "leaves the identifier of a Blueprint that is not embedded" do
    igniter = migrate(%{@partner_path => @partner})
    assert source(igniter, @partner_path) =~ ~s(identifier "{{ entry.name }}")
  end

  test "leaves the identifier of a Blueprint that shares a file with an embedded one" do
    igniter = migrate(%{@project_path => @project <> "\n" <> @property})
    migrated = source(igniter, @project_path)

    assert migrated =~ ~s(identifier "{{ entry.title }}")
    assert migrated =~ "data_layer :embedded\n  identifier false\n"
  end

  test "writes an image cfg's default_srcset as srcset: %{default: …}" do
    igniter = migrate(%{@partner_path => @partner})
    partner = source(igniter, @partner_path)

    refute partner =~ "default_srcset"

    assert partner =~ """
               srcset: %{
                 default: [
                   {"small", "700w"},
                   {"xlarge", "1900w"}
                 ]
               }
           """

    assert_has_notice(igniter, &(&1 =~ "#{@partner_path}:19: `default_srcset:` is now `srcset: %{default: …}`"))

    rerun = igniter |> apply_igniter!() |> include_test_files() |> Migrate55.igniter()
    assert_unchanged(rerun, @partner_path)
  end

  test "drops default_srcset beside a srcset, which 0.53 used instead" do
    partner =
      String.replace(@partner, ~s|default_size: "xlarge",|, ~s|default_size: "xlarge",\n    srcset: [{"small", "700w"}],|)

    igniter = migrate(%{@partner_path => partner})
    migrated = source(igniter, @partner_path)

    refute migrated =~ "default_srcset"
    assert migrated =~ ~s|srcset: [{"small", "700w"}]|
    assert_has_notice(igniter, &(&1 =~ "#{@partner_path}:20: `default_srcset:` removed"))
  end

  test "lists every read of an :entries relation, which holds join rows since 0.54" do
    igniter = migrate(%{@project_path => @project, @controller_path => @controller})

    assert_unchanged(igniter, @controller_path)

    assert_has_warning(igniter, fn warning ->
      warning =~ "#{@controller_path}:6: ids = Enum.map(project.related_entries || [], & &1.entry_id)" and
        warning =~ "& &1.identifier.entry_id" and
        not (warning =~ "#{@controller_path}:12:")
    end)
  end

  test "leaves the identifier of a Blueprint whose nested module is embedded" do
    nested =
      String.replace(
        @project,
        "  relations do",
        """
          defmodule Property do
            use Brando.Blueprint,
              application: "Koi",
              domain: "Projects",
              schema: "Property",
              singular: "property",
              plural: "properties"

            data_layer :embedded
            identifier "{{ entry.id }}"
          end

          relations do
        """
      )

    migrated = migrate(%{@project_path => nested}) |> source(@project_path)

    assert migrated =~ ~s(identifier "{{ entry.title }}")
    assert migrated =~ "data_layer :embedded\n    identifier false\n"
  end

  test "rewrites default_srcset only in an asset cfg, not in other data" do
    partner =
      String.replace(@partner, "  attributes do", """
        def picture_options, do: %{default_srcset: [{"small", "700w"}]}

        attributes do
      """)

    migrated = migrate(%{@partner_path => partner}) |> source(@partner_path)

    assert migrated =~ ~s|def picture_options, do: %{default_srcset: [{"small", "700w"}]}|
    assert migrated =~ "srcset: %{\n      default: ["
  end

  test "rewrites default_srcset in a cfg given inline" do
    partner =
      @partner
      |> String.replace(
        "asset :logo, :image, cfg: @logo_cfg",
        ~s|asset :logo, :image, cfg: [upload_path: "x", default_srcset: [{"small", "700w"}]]|
      )

    migrated = migrate(%{@partner_path => partner}) |> source(@partner_path)

    assert migrated =~ ~s|cfg: [upload_path: "x", srcset: %{default: [{"small", "700w"}]}]|
    # The attribute no asset reads as its cfg is left alone.
    assert migrated =~ "default_srcset: [\n      {\"small\", \"700w\"},"
  end

  test "rewrites default_srcset only in the attribute given as cfg, beside another on its line" do
    partner =
      String.replace(
        @partner,
        "  attributes do",
        "  @small_cfg [default_srcset: []]; @display_opts %{default_srcset: []}\n\n  attributes do"
      )
      |> String.replace("asset :logo, :image, cfg: @logo_cfg", "asset :logo, :image, cfg: @small_cfg")

    migrated = migrate(%{@partner_path => partner}) |> source(@partner_path)

    assert migrated =~ "@small_cfg [srcset: %{default: []}]"
    assert migrated =~ "@display_opts %{default_srcset: []}"
  end

  test "lists a read of an :entries relation whose line has .identifier only in a string" do
    controller = """
    defmodule KoiWeb.ProjectController do
      def ids(project) do
        Enum.map(project.related_entries, & &1.entry_id) |> IO.inspect(label: ".identifier")
      end
    end
    """

    igniter = migrate(%{@project_path => @project, @controller_path => controller})
    assert_has_warning(igniter, &(&1 =~ "#{@controller_path}:3:"))
  end

  test "lists a read of an :entries relation whose line mentions .identifier only in a comment" do
    controller = """
    defmodule KoiWeb.ProjectController do
      def ids(project) do
        Enum.map(project.related_entries, & &1.entry_id) # preload .identifier
      end

      def titles(project), do: Enum.map(project.related_entries, & &1.identifier.title)
    end
    """

    igniter = migrate(%{@project_path => @project, @controller_path => controller})

    assert_has_warning(igniter, fn warning ->
      warning =~ "#{@controller_path}:3:" and not (warning =~ "#{@controller_path}:6:")
    end)
  end

  defp migrate(files) do
    [app_name: :koi, files: Map.put(files, ".formatter.exs", @formatter)]
    |> test_project()
    |> include_test_files()
    |> Migrate55.igniter()
  end

  defp source(igniter, path), do: igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)

  defp include_test_files(igniter) do
    Enum.reduce(Map.keys(igniter.assigns.test_files), igniter, &Igniter.include_existing_file(&2, &1))
  end
end
