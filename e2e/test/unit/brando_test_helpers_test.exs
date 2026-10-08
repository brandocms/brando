defmodule E2eProject.BrandoTestHelpersTest do
  # Brando.Test as a project uses it: the E2E app's own blueprint, module and
  # admin form. Not async: the form's LiveView shares the test's sandbox.
  use E2eProjectWeb.ConnCase, async: false

  alias E2eProject.Projects.{Client, Project}

  setup do
    user = insert_user(role: :superuser)

    {:ok, module} =
      Brando.Content.create_module(
        %{
          uid: "helpers#{System.unique_integer([:positive])}",
          name: %{"en" => "Quote"},
          namespace: %{"en" => "Tests"},
          help_text: %{"en" => "A quote"},
          class: "quote",
          code: ~s(<blockquote class="quote">{% ref refs.text %}<cite>{{ author }}</cite></blockquote>),
          refs: [%{name: "text", uid: Brando.Utils.generate_uid(), data: %{type: "text", data: %{text: "Quoted"}}}],
          vars: [%{type: "string", key: "author", label: "Author", value: "Anonymous"}]
        },
        user
      )

    %{user: user, module: module}
  end

  test "renders a module as the site does", %{module: module} do
    html = render_block(module, vars: %{"author" => "Ada"}, refs: %{"text" => %{text: "<p>Hello</p>"}})
    assert html =~ ~s(<blockquote class="quote">)
    assert html =~ "<p>Hello</p>"
    assert html =~ "<cite>Ada</cite>"
  end

  test "a factory builds a project with its required client", %{user: user, module: module} do
    project = insert_entry(Project, %{title: "Sommerro"}, user: user, blocks: [{module, vars: %{"author" => "Ada"}}])

    assert %Project{title: "Sommerro", status: :published, client_id: client_id} = project
    assert %Client{} = E2eProject.Repo.get!(Client, client_id)
    assert project.rendered_blocks =~ "<cite>Ada</cite>"
  end

  test "edits a project in its admin form", %{conn: conn, user: user, module: module} do
    project = insert_entry(Project, %{title: "Before"}, user: user)
    {conn, _user} = log_in_as(conn, role: :superuser)

    {view, _html} = open_form(conn, project)
    fill_form(view, Project, title: "After")
    add_block(view, Project, module)
    assert {:ok, _path} = save_form(view, Project)

    project = E2eProject.Repo.get!(Project, project.id)
    assert project.title == "After"
    assert project.rendered_blocks =~ "<cite>Anonymous</cite>"
  end
end
