defmodule Brando.Migrations.RewriteMultiModuleEntryPathsTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Brando.Test.Support, only: [preserve_cache: 1]

  alias Brando.Factory
  alias BrandoIntegration.Repo

  @migration Application.app_dir(
               :brando,
               "priv/templates/brando.upgrade/migrations/brando_219_rewrite_multi_module_entry_paths.exs"
             )
  @tenant "tenant_acme_staging"

  # Module 47 on koi, as the blocks conversion left it
  @koi """
  <div class="services">
    <div class="canvas">
      {% assign first_entry = entries.first %}
      <img src="{{ first_entry.data.vars.hover_image|src:"large" }}" width="{{ first_entry.data.vars.hover_image.width }}" alt="" />
      <div class="text">{{ first_entry.data.vars.text }}</div>
    </div>
    <div class="list">
      {% for link in entries %}
        {% if forloop.last == true %} og {% endif %}
        <a href="{{ link.data.vars.url }}" data-hover-text="{{ link.data.vars.text }}">{{ link.data.vars.link_text }}</a>
      {% endfor %}
    </div>
  </div>
  {{ content | renderless }}
  """

  setup_all do
    [{module, _bytecode}] = Code.compile_file(@migration)

    on_exit(fn ->
      :code.purge(module)
      :code.delete(module)
    end)

    %{migration: module}
  end

  describe "rewrite/1" do
    test "fixes koi's services module, and leaves the result alone", %{migration: migration} do
      fixed = migration.rewrite(@koi)

      assert fixed == String.replace(@koi, ".data.vars.", ".vars.")
      assert migration.rewrite(fixed) == fixed
    end

    test "rewrites loop variables over entries in Liquid, not in HTML or strings", %{migration: migration} do
      code = """
      <p class="link.data.vars.url">{{ 'link.data.vars.url' }}</p>
      {%- for link in entries limit: 3 -%}
        {% if link.data.refs.cover %}<a href="{{ link.data.vars.url }}">{{ link.data.vars.text }}</a>{% endif %}
        {% assign v = link.data.vars %}{{ v.text }}
        {% for image in link.data.refs.gallery.gallery_objects %}{{ image.image.path }}{% endfor %}
      {%- endfor -%}
      {% tablerow cell in entries cols: 2 %}{{ cell.data.vars.text }}{% endtablerow %}
      {% for link in other_links %}{{ link.data.vars.url }}{% endfor %}
      """

      assert migration.rewrite(code) == """
             <p class="link.data.vars.url">{{ 'link.data.vars.url' }}</p>
             {%- for link in entries limit: 3 -%}
               {% if link.refs.cover %}<a href="{{ link.vars.url }}">{{ link.vars.text }}</a>{% endif %}
               {% assign v = link.vars %}{{ v.text }}
               {% for image in link.refs.gallery.gallery_objects %}{{ image.image.path }}{% endfor %}
             {%- endfor -%}
             {% tablerow cell in entries cols: 2 %}{{ cell.vars.text }}{% endtablerow %}
             {% for link in other_links %}{{ link.data.vars.url }}{% endfor %}
             """
    end

    test "rewrites entries assigned one at a time, read directly, or through a list alias", %{migration: migration} do
      code = """
      {{ last.data.vars.text }}
      {% assign last = entries | last %}{{ last.data.vars.text }}
      {% assign second = entries[1] %}{{ second.data.refs.cover }}
      {{ entries.first.data.vars.text }} {{ entries[2].data.vars.text }}
      {% assign sorted = entries | sort: "data.vars.order" | reverse %}
      {% for link in sorted %}{{ link.data.vars.url }}{% endfor %}
      {% assign top = sorted.first %}{{ top.data.vars.url }} {{ sorted.last.data.vars.url }}
      {% assign names = entries | map: "data.vars.name" %}{% for name in names %}{{ name.data.vars.x }}{% endfor %}
      """

      assert migration.rewrite(code) == """
             {{ last.data.vars.text }}
             {% assign last = entries | last %}{{ last.vars.text }}
             {% assign second = entries[1] %}{{ second.refs.cover }}
             {{ entries.first.vars.text }} {{ entries[2].vars.text }}
             {% assign sorted = entries | sort: "vars.order" | reverse %}
             {% for link in sorted %}{{ link.vars.url }}{% endfor %}
             {% assign top = sorted.first %}{{ top.vars.url }} {{ sorted.last.vars.url }}
             {% assign names = entries | map: "vars.name" %}{% for name in names %}{{ name.data.vars.x }}{% endfor %}
             """
    end
  end

  test "koi's services module renders its entries' vars once rewritten, and nothing before", %{migration: migration} do
    preserve_cache([:navigation, :globals, :identity])
    user = Factory.insert(:random_user)

    {:ok, child} =
      Brando.Content.create_module(Factory.params_for(:module, %{code: "<!-- entry -->", refs: [], vars: []}), user)

    entry = fn n ->
      %{
        type: :module,
        module_id: child.id,
        active: true,
        uid: Brando.Utils.generate_uid(),
        refs: [],
        vars: [
          %{key: "url", label: "URL", type: :string, value: "/service-#{n}"},
          %{key: "text", label: "Text", type: :string, value: "Hover #{n}"},
          %{key: "link_text", label: "Link", type: :string, value: "Service #{n}"}
        ]
      }
    end

    render = fn code ->
      {:ok, parent} =
        Brando.Content.create_module(Factory.params_for(:module, %{code: code, multi: true, refs: [], vars: []}), user)

      block = %{
        block: %{
          type: :module,
          source: "Elixir.Brando.Pages.Page.Blocks",
          module_id: parent.id,
          multi: true,
          uid: Brando.Utils.generate_uid(),
          refs: [],
          vars: [],
          children: [entry.(1), entry.(2)]
        }
      }

      Brando.Villain.parse([block], %Brando.Pages.Page{})
    end

    assert render.(@koi) =~ ~s(<a href="" data-hover-text=""></a>)

    html = render.(migration.rewrite(@koi))
    assert html =~ ~s(<div class="text">Hover 1</div>)
    assert html =~ ~s(<a href="/service-1" data-hover-text="Hover 1">Service 1</a>)
    assert html =~ ~s(<a href="/service-2" data-hover-text="Hover 2">Service 2</a>)
  end

  test "rewrites stored module code in public and every environment", %{migration: migration} do
    Brando.MigrationTemplates.create_environment(@tenant, ["content_modules"])

    insert = fn schema, code, extra ->
      %{rows: [[id]]} =
        Repo.query!(
          """
          INSERT INTO "#{schema}".content_modules (uid, class, code, datasource, type, inserted_at, updated_at)
          VALUES ($1, 'm', $2, $3, $4, NOW(), NOW()) RETURNING id
          """,
          [Brando.Utils.generate_uid(), code, extra[:datasource] || false, extra[:type] || "liquid"]
        )

      {schema, id}
    end

    datasource = "{% for entry in entries %}{{ entry.data.vars.x }}{% endfor %}"
    multi = for schema <- ["public", @tenant], do: insert.(schema, @koi, %{})
    untouched = [insert.("public", datasource, %{datasource: true}), insert.("public", datasource, %{type: "heex"})]

    for _run <- 1..2 do
      Ecto.Migrator.up(Repo, System.unique_integer([:positive]), migration, log: false, migration_lock: false)

      for {schema, id} <- multi do
        assert code(schema, id) == String.replace(@koi, ".data.vars.", ".vars.")
      end

      for {schema, id} <- untouched, do: assert(code(schema, id) == datasource)
    end
  end

  defp code(schema, id) do
    %{rows: [[code]]} = Repo.query!(~s(SELECT code FROM "#{schema}".content_modules WHERE id = $1), [id])
    code
  end
end
