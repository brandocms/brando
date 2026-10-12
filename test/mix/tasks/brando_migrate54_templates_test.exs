defmodule Mix.Tasks.Brando.Migrate54TemplatesTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  alias Mix.Tasks.Brando.Migrate54

  @navigation_path "lib/lett_web/components/partials/navigation.html.heex"

  test "rewrites navigation item reads inside a generator over the navigation's items" do
    navigation = """
    <section class="main">
      <ul>
        <%= for item <- @navigation.items do %>
          <%= if item.status == :published do %>
            <li>
              <a class={Brando.HTML.active(@conn, "\#{item.url}/*")} href={item.url}>
                <%= item.title %>
              </a>
            </li>
          <% end %>
        <% end %>
      </ul>
    </section>
    """

    igniter = migrate(%{@navigation_path => navigation})

    assert source(igniter, @navigation_path) == """
           <section class="main">
             <ul>
               <%= for item <- @navigation.items do %>
                 <%= if item.status == :published do %>
                   <li>
                     <a class={Brando.HTML.active(@conn, "\#{Brando.HTML.get_menu_item_url(item)}/*")} href={Brando.HTML.get_menu_item_url(item)}>
                       <%= Brando.HTML.get_menu_item_text(item) %>
                     </a>
                   </li>
                 <% end %>
               <% end %>
             </ul>
           </section>
           """

    refute Enum.any?(igniter.warnings, &(&1 =~ "Navigation items"))

    rerun = igniter |> apply_igniter!() |> include_test_files() |> Migrate54.igniter()
    assert_unchanged(rerun, [@navigation_path])
  end

  test "rewrites :for item reads, sub-items and their reads" do
    navigation = """
    <li :for={item <- @menu.items}>
      <a href={item.url} target={item.open_in_new_window && "_blank"}>{item.title}</a>
      <ul :if={item.items != []}>
        <li :for={child <- item.items}><a href={child.url}>{child.title}</a></li>
      </ul>
    </li>
    """

    igniter = migrate(%{@navigation_path => navigation})

    assert source(igniter, @navigation_path) == """
           <li :for={item <- @menu.items}>
             <a href={Brando.HTML.get_menu_item_url(item)} target={Brando.HTML.get_menu_item_target_blank(item) && "_blank"}>{Brando.HTML.get_menu_item_text(item)}</a>
             <ul :if={item.children != []}>
               <li :for={child <- item.children}><a href={Brando.HTML.get_menu_item_url(child)}>{Brando.HTML.get_menu_item_text(child)}</a></li>
             </ul>
           </li>
           """
  end

  test "lists navigation item reads it cannot tell apart from other data" do
    navigation = """
    <a :for={item <- @navigation.items} href={item.url}>{item.title}</a>
    <a :for={item <- @products} href={item.url}>{item.title}</a>
    """

    in_text = """
    <%= for item <- @navigation.items do %>
      <p>Link: item.url</p><a href={item.url}></a>
    <% end %>
    """

    text_path = "lib/lett_web/components/partials/footer.html.heex"
    igniter = migrate(%{@navigation_path => navigation, text_path => in_text})

    assert_unchanged(igniter, [@navigation_path])

    assert source(igniter, text_path) == """
           <%= for item <- @navigation.items do %>
             <p>Link: item.url</p><a href={Brando.HTML.get_menu_item_url(item)}></a>
           <% end %>
           """

    assert_has_warning(igniter, fn warning ->
      warning =~ "Navigation items" and
        warning =~ "#{@navigation_path}:1: <a :for={item <- @navigation.items} href={item.url}>" and
        warning =~ "#{text_path}:2: <p>Link: item.url</p>"
    end)
  end

  defp migrate(files) do
    [app_name: :lett, files: files]
    |> test_project()
    |> include_test_files()
    |> Migrate54.igniter()
  end

  defp source(igniter, path), do: igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)

  defp include_test_files(igniter) do
    Enum.reduce(Map.keys(igniter.assigns.test_files), igniter, &Igniter.include_existing_file(&2, &1))
  end
end
