defmodule Mix.Tasks.Brando.Migrate54ListingRowsTest do
  use ExUnit.Case, async: false

  import Igniter.Test

  alias Mix.Tasks.Brando.Migrate54

  @path "lib/lett/articles/article.ex"

  @article """
  defmodule Lett.Articles.Article do
    use Brando.Blueprint,
      application: "Lett",
      domain: "Articles",
      schema: "Article",
      singular: "article",
      plural: "articles"

    import LettAdmin.Gettext

    trait Brando.Trait.Sequenced

    listings do
      listing do
        listing_query %{preload: [:category]}

        filters([
          [label: t("Title"), filter: "title"]
        ])

        field :language, :language, columns: 1

        field :cover, :image, columns: 2, class: "padded"

        template(
          \"""
          <div class="badge no-border">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="12" height="12"><path fill="none" d="M0 0h24v24H0z"/><path d="M10.9 2.1l9.899 1.415z"/></svg>
            {{ entry.category.name }}
          </div><br>
          <a
            data-phx-link="redirect"
            data-phx-link-state="push"
            href="/admin/articles/articles/update/{{ entry.id }}"
            class="entry-link">
            {% if entry.featured %} ⭐️ {% endif %}
            {{ entry.title }}
          </a>
          \""",
          columns: 6
        )
      end
    end

    def get_category(id) do
      Lett.Articles.get_category(id)
    end
  end
  """

  @article_row ~S'''
    def get_category(id) do
      Lett.Articles.get_category(id)
    end

    def listing_row(assigns) do
      ~H"""
      <.cover image={@entry.cover} columns={2} padded />
      <.update_link entry={@entry} columns={6}>
        <:before>
          <div class="badge no-border">
            {@entry.category && @entry.category.name}
          </div>
          <br />
        </:before>
        <span :if={@entry.featured}>⭐️</span>
        {@entry.title}
      </.update_link>
      """
    end
  end
  '''

  @menuitem """
  defmodule Lett.Menu.Menuitem do
    use Brando.Blueprint,
      application: "Lett",
      domain: "Menu",
      schema: "Menuitem",
      singular: "menuitem",
      plural: "menuitems"

    listings do
      listing do
        field :language, :language, columns: 1
        field :cover, :image, columns: 2, class: "padded"

        template(
          \"""
          <div class="badge">{{ entry.category.name }}</div>{% if entry.seasonal %}<div class="badge">sesong</div>{% endif %}<br>
          <a
            data-phx-link="redirect"
            data-phx-link-state="push"
            href="/admin/menu/menuitems/update/{{ entry.id }}"
            class="entry-link">
            {{ entry.name }}
          </a>


          \""",
          columns: 6
        )
      end
    end
  end
  """

  @menuitem_row ~S'''
    def listing_row(assigns) do
      ~H"""
      <.cover image={@entry.cover} columns={2} padded />
      <.update_link entry={@entry} columns={6}>
        <:before>
          <div class="badge">{@entry.category && @entry.category.name}</div>
          <div :if={@entry.seasonal} class="badge">sesong</div>
          <br />
        </:before>
        {@entry.name}
      </.update_link>
      """
    end
  '''

  @category """
  defmodule Lett.Articles.Category do
    use Brando.Blueprint,
      application: "Lett",
      domain: "Articles",
      schema: "Category",
      singular: "category",
      plural: "categories"

    listings do
      listing do
        field :language, :language, columns: 1

        template(
          \"""
          <a
            data-phx-link="redirect"
            data-phx-link-state="push"
            href="/admin/articles/categories/update/{{ entry.id }}"
            class="entry-link">
            {{ entry.name }}
          </a>
          \""",
          columns: 8
        )
      end
    end
  end
  """

  @category_row ~S'''
    def listing_row(assigns) do
      ~H"""
      <.update_link entry={@entry} columns={8}>{@entry.name}</.update_link>
      """
    end
  '''

  @restaurant """
  defmodule Lett.Restaurants.Restaurant do
    use Brando.Blueprint,
      application: "Lett",
      domain: "Restaurants",
      schema: "Restaurant",
      singular: "restaurant",
      plural: "restaurants"

    listings do
      listing do
        field :language, :language, columns: 1

        template(
          \"""
          <div class="badge no-border">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="12" height="12"><path fill="none" d="M0 0h24v24H0z"/><path d="M21 19h2v2H1v-2h2V4z"/></svg>
            {{ entry.city }}, {{ entry.address }}
          </div><br>
          <a
            data-phx-link="redirect"
            data-phx-link-state="push"
            href="/admin/restaurants/restaurants/update/{{ entry.id }}"
            class="entry-link">
            {{ entry.name }}
          </a>


          \""",
          columns: 8
        )
      end
    end
  end
  """

  @restaurant_row ~S'''
    def listing_row(assigns) do
      ~H"""
      <.update_link entry={@entry} columns={8}>
        <:before>
          <div class="badge no-border">
            {@entry.city}, {@entry.address}
          </div>
          <br />
        </:before>
        {@entry.name}
      </.update_link>
      """
    end
  '''

  test "writes an Article's badge, featured star and cover as a row component" do
    igniter = migrate(@article)
    blueprint = source(igniter, @path)

    assert String.ends_with?(blueprint, @article_row)
    assert blueprint =~ "component(&__MODULE__.listing_row/1)"
    refute blueprint =~ "field("
    refute blueprint =~ "template("
    refute blueprint =~ "svg"

    assert blueprint =~
             ~r/use Brando.Blueprint,[^\n]*(\n [^\n]*)*\n\n  import Brando.Blueprint.Listings.Components.Core\n  import Brando.Blueprint.Listings.Components.Cover, only: \[cover: 1\]\n/

    assert blueprint =~ ~s|key: "title"\n      )\n\n      component(&__MODULE__.listing_row/1)\n    end|

    assert_has_notice(igniter, fn notice ->
      notice =~ "Legacy listing columns (`field`, `template`) became row components" and
        notice =~ "Compare each listing with the old one:\n\n  #{@path}\n" and
        notice =~ "only entries in the editor's content language.\n\n  #{@path}\n" and
        notice =~ "icon on a line of its own.\n\n  #{@path}\n"
    end)
  end

  test "writes a Menuitem's conditional badge, a Category's link and a Restaurant's two values" do
    for {blueprint, path, row, imports} <- [
          {@menuitem, "lib/lett/menu/menuitem.ex", @menuitem_row, ["Core", "Cover, only: [cover: 1]"]},
          {@category, "lib/lett/articles/category.ex", @category_row, ["Core"]},
          {@restaurant, "lib/lett/restaurants/restaurant.ex", @restaurant_row, ["Core"]}
        ] do
      migrated = blueprint |> migrate(path) |> source(path)

      assert String.ends_with?(migrated, row <> "end\n")
      assert migrated =~ "      component(&__MODULE__.listing_row/1)\n    end\n  end"
      refute migrated =~ ~r/\bfield\(|template\(|svg|entry-link/

      assert Regex.scan(~r/import Brando\.Blueprint\.Listings\.Components\.(.*)/, migrated, capture: :all_but_first) ==
               Enum.map(imports, &[&1])
    end
  end

  test "rows compile, and migrate55 adds no listing imports to them" do
    igniter = migrate(@menuitem, "lib/lett/menu/menuitem.ex")
    migrated = source(igniter, "lib/lett/menu/menuitem.ex")

    module = Module.concat(__MODULE__, "Menuitem#{System.unique_integer([:positive])}")

    compiled =
      migrated
      |> String.replace("Lett.Menu.Menuitem", inspect(module))
      |> String.replace(~s|plural: "menuitems"|, ~s|plural: "menuitems",\n    gettext_module: Brando.Gettext|)
      |> String.replace("trait(Brando.Trait.Sequenced)", "")

    warnings = ExUnit.CaptureIO.capture_io(:stderr, fn -> Code.compile_string(compiled) end)
    refute warnings =~ "no longer supported"
    assert [%{component: component}] = module.__listings__()
    assert is_function(component, 1)

    rerun =
      igniter
      |> apply_igniter!()
      |> Igniter.include_existing_file("lib/lett/menu/menuitem.ex")
      |> Mix.Tasks.Brando.Migrate55.igniter()

    rerun_source = source(rerun, "lib/lett/menu/menuitem.ex")
    assert count(rerun_source, "import Brando.Blueprint.Listings.Components.Core") == 1
    assert count(rerun_source, "import Brando.Blueprint.Listings.Components.Cover") == 1
  end

  test "writes a named listing's url field and a template without a link" do
    blueprint = """
    defmodule Lett.Articles.Article do
      use Brando.Blueprint,
        application: "Lett",
        domain: "Articles",
        schema: "Article",
        singular: "article",
        plural: "articles"

      listings do
        listing :compact do
          template "{{ entry.title }}", columns: 4, class: "small"
          field :url, :url
        end
      end
    end
    """

    migrated = blueprint |> migrate() |> source(@path)

    assert migrated =~ "listing :compact do\n      component(&__MODULE__.compact_listing_row/1)\n    end"

    assert String.ends_with?(migrated, ~S'''
             def compact_listing_row(assigns) do
               ~H"""
               <.field columns={4} class="small">{@entry.title}</.field>
               <.url entry={@entry} />
               """
             end
           end
           ''')

    assert count(migrated, "import Brando.Blueprint.Listings.Components.Core") == 1
    refute migrated =~ "Components.Cover"
  end

  # koi's 0.53 listings: categories looped over after the link, a palette
  # swatch with Liquid in its attributes, and contact lines after the link.
  defp koi_blueprint(schema, columns) do
    """
    defmodule Lett.Koi.#{schema} do
      use Brando.Blueprint,
        application: "Lett",
        domain: "Koi",
        schema: "#{schema}",
        singular: "#{Macro.underscore(schema)}",
        plural: "#{Macro.underscore(schema)}s"

      listings do
        listing do
          field :language, :language, columns: 1
          field :cover, :image, columns: 2, class: "padded"

    #{columns}
        end
      end
    end
    """
  end

  test "writes koi's loops over an association and markup after the link into the row" do
    article =
      koi_blueprint("Article", ~S'''
            template(
              """
              <a
                data-phx-link="redirect"
                data-phx-link-state="push"
                href="/admin/articles/articles/update/{{ entry.id }}"
                class="entry-link">
                {{ entry.title }}
              </a>
              <br>
              {% for category in entry.categories %}
                <small>{{ category.name }}</small>
              {% endfor %}
              """,
              columns: 5
            )

            field :url, :url
      ''')

    project =
      koi_blueprint("Project", ~S'''
            template(
              """
              <div class="circle-stack">
              {% if entry.palette %}
                <div class="circle" data-color-no="0" data-popover="{{ entry.palette.colors[0].hex_value }}" style="background-color: {{ entry.palette.colors[0].hex_value }}"></div>
              {% endif %}
              </div>
              """,
              columns: 1
            )

            template(
              """
              <a
                data-phx-link="redirect"
                data-phx-link-state="push"
                href="/admin/projects/projects/update/{{ entry.id }}"
                class="entry-link">
                {{ entry.title }}
              </a>
              <br>
              {% for category in entry.categories %}
                <small>{{ category.name }}</small>
              {% endfor %}
              """,
              columns: 4
            )

            field :url, :url
      ''')

    member =
      koi_blueprint("Member", ~S'''
            template(
              """
              <a
                data-phx-link="redirect"
                data-phx-link-state="push"
                href="/admin/team/members/update/{{ entry.id }}"
                class="entry-link">
                {{ entry.name }}
              </a><br>
              <small>{{ entry.email }}</small><br>
              <small>{{ entry.phone }}</small><br>
              """,
              columns: 7
            )
      ''')

    assert row(article, "Article") == ~S'''
             def listing_row(assigns) do
               ~H"""
               <.cover image={@entry.cover} columns={2} padded />
               <.update_link entry={@entry} columns={5}>
                 {@entry.title}
                 <:outside>
                   <br />
                   <small :for={category <- @entry.categories || []}>{category.name}</small>
                 </:outside>
               </.update_link>
               <.url entry={@entry} />
               """
             end
           '''

    assert row(project, "Project") == ~S'''
             def listing_row(assigns) do
               ~H"""
               <.cover image={@entry.cover} columns={2} padded />
               <.field columns={1}>
                 <div class="circle-stack">
                   <div
                     :if={@entry.palette}
                     class="circle"
                     data-color-no="0"
                     data-popover={
                       Enum.at(@entry.palette.colors || [], 0) &&
                         Enum.at(@entry.palette.colors || [], 0).hex_value
                     }
                     style={"background-color: #{Enum.at(@entry.palette.colors || [], 0) && Enum.at(@entry.palette.colors || [], 0).hex_value}"}
                   >
                   </div>
                 </div>
               </.field>
               <.update_link entry={@entry} columns={4}>
                 {@entry.title}
                 <:outside>
                   <br />
                   <small :for={category <- @entry.categories || []}>{category.name}</small>
                 </:outside>
               </.update_link>
               <.url entry={@entry} />
               """
             end
           '''

    assert row(member, "Member") == ~S'''
             def listing_row(assigns) do
               ~H"""
               <.cover image={@entry.cover} columns={2} padded />
               <.update_link entry={@entry} columns={7}>
                 {@entry.name}
                 <:outside>
                   <br />
                   <small>{@entry.email}</small>
                   <br />
                   <small>{@entry.phone}</small>
                   <br />
                 </:outside>
               </.update_link>
               """
             end
           '''
  end

  test "koi's converted rows compile" do
    blueprint =
      koi_blueprint("Article", ~S'''
            template(
              """
              <a href="/admin/articles/articles/update/{{ entry.id }}" class="entry-link">{{ entry.title }}</a>
              {% for category in entry.categories %}<small>{{ category.name }}</small>{% endfor %}
              """,
              columns: 5
            )
          end

          listing :swatches do
            template(
              """
              {% for category in entry.categories %}<small title="{{ category.name }} ({{ entry.title }})">{{ category.name }}</small>{% endfor %}
              <div class="swatch" style="color: {{ entry.palette.colors[0].hex_value }}"></div>
              """,
              columns: 5
            )
      ''')

    path = "lib/lett/koi/article.ex"
    migrated = blueprint |> migrate(path) |> source(path)
    module = Module.concat(__MODULE__, "Article#{System.unique_integer([:positive])}")

    compiled =
      migrated
      |> String.replace("Lett.Koi.Article", inspect(module))
      |> String.replace(~s|plural: "articles"|, ~s|plural: "articles",\n    gettext_module: Brando.Gettext|)

    warnings = ExUnit.CaptureIO.capture_io(:stderr, fn -> Code.compile_string(compiled) end)
    assert warnings == ""

    entry = %{title: "Koi", categories: [%{name: "Fish"}], palette: %{colors: [%{hex_value: "#fff"}]}}

    html =
      %{entry: entry, __changed__: nil}
      |> module.swatches_listing_row()
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()

    assert html =~ ~s|title="Fish (Koi)"|
    assert html =~ ~s|style="color: #fff"|

    # Liquid renders nothing for a missing association; so does the row.
    html =
      %{entry: %{entry | categories: nil, palette: %{colors: nil}}, __changed__: nil}
      |> module.swatches_listing_row()
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()

    refute html =~ "<small"
    assert html =~ ~s|style="color: "|
  end

  test "reads a loop variable that shadows `entry` as the loop variable" do
    blueprint =
      koi_blueprint("Article", ~S'''
            template(
              """
              {% for entry in entry.children %}<b>{{ entry.title }}</b>{% endfor %}
              {% if entry.parent %}<i>{% for entry in entry.children %}{{ entry.parent.title }}{% endfor %}</i>{% endif %}
              """,
              columns: 5
            )
      ''')

    row = blueprint |> row("Article") |> String.replace(~r/\s*\n\s*/, " ")
    assert row =~ ~s|<b :for={entry <- @entry.children \|\| []}>{entry.title}</b>|

    # The outer `{% if %}` tested the entry's parent, not the loop variable's.
    assert row =~
             ~s|<i :if={@entry.parent}><span :for={entry <- @entry.children \|\| []}>{entry.parent && entry.parent.title}</span></i>|
  end

  defp row(blueprint, schema) do
    path = "lib/lett/koi/#{Macro.underscore(schema)}.ex"
    migrated = blueprint |> migrate(path) |> source(path)
    [_, row] = String.split(migrated, "\n\n  def listing_row", parts: 2)
    "  def listing_row" <> String.replace_suffix(row, "end\n", "")
  end

  test "is idempotent" do
    igniter = migrate(@article)

    rerun =
      igniter
      |> apply_igniter!()
      |> Igniter.include_existing_file(@path)
      |> Migrate54.igniter()

    assert_unchanged(rerun, @path)
  end

  test "leaves a listing it cannot convert entirely as it is, and names the line" do
    blueprint =
      String.replace(
        @article,
        "{{ entry.title }}",
        "{{ entry.title | upcase }}"
      )

    igniter = migrate(blueprint)
    migrated = source(igniter, @path)

    assert migrated =~ ~r/field\(:language, :language, columns: 1\)/
    assert migrated =~ ~r/field\(:cover, :image, columns: 2, class: "padded"\)/
    assert migrated =~ "{{ entry.title | upcase }}"
    assert migrated =~ "<svg"
    refute migrated =~ "listing_row"
    refute migrated =~ "Listings.Components"

    assert_has_warning(igniter, fn warning ->
      warning =~ "Legacy listing columns (`field`, `template`) left as they are" and
        warning =~ "guides/blueprint_listings.md#rows" and
        warning =~ "#{@path}:26: the Liquid `{{ entry.title | upcase }}`"
    end)
  end

  test "names each shape it does not convert" do
    for {from, to, reason} <- [
          {"class=\"entry-link\">", "class=\"entry-link\" target=\"_blank\">",
           "a link with attributes other than `href` and `class`"},
          {"/admin/articles/articles/update/{{ entry.id }}", "/articles/{{ entry.slug }}",
           "a link that is not to the entry's update form"},
          {"</a>", "</a><a href=\"/admin/x/update/{{ entry.id }}\">x</a>",
           "a template with a link that is not its only one"},
          {"{% if entry.featured %}", "{% for tag in entry.tags limit:2 %}",
           "the Liquid tag `{% for tag in entry.tags limit:2 %}`"},
          {"{% if entry.featured %} ⭐️ {% endif %}", "{% for tag in tags %}{{ tag }}{% endfor %}",
           "the Liquid `{% for tag in tags %}`"},
          {"{% if entry.featured %} ⭐️ {% endif %}",
           "{% for tag in entry.tags %}<b>{{ tag.name }}</b><i>{{ tag.slug }}</i>{% endfor %}",
           "a `{% for tag in entry.tags %}` around more than one element"},
          {"field :cover, :image, columns: 2, class: \"padded\"", "field :children, :children_button, columns: 1",
           "#{@path}:24: a `:children_button` field"},
          {"field :cover, :image, columns: 2, class: \"padded\"", "field :cover, :image, class: \"padded\"",
           "#{@path}:24: an image field without a literal `columns:`"}
        ] do
      igniter = @article |> String.replace(from, to) |> migrate()

      refute source(igniter, @path) =~ "listing_row"
      assert_has_warning(igniter, &(&1 =~ reason))
    end
  end

  defp migrate(blueprint, path \\ @path) do
    [app_name: :lett, files: %{path => blueprint}]
    |> test_project()
    |> Igniter.include_existing_file(path)
    |> Migrate54.igniter()
  end

  defp source(igniter, path) do
    igniter.rewrite
    |> Rewrite.source!(path)
    |> Rewrite.Source.get(:content)
  end

  defp count(content, pattern), do: content |> String.split(pattern) |> length() |> Kernel.-(1)
end
