defmodule BrandoAdmin.HeexBlockModuleBoundTest do
  # The block editor compiles a HEEx module's template once per template, not
  # once per block: inserting blocks, saved or not, loads no more modules.
  use Brando.LiveCase

  alias BrandoAdmin.Components.Form.BlockField

  @block_field "page_form-blocks-blocks"

  setup %{current_user: user} do
    {:ok, page: Factory.insert(:page, creator: user)}
  end

  defp loaded_for(code) do
    suffix = "_#{:erlang.phash2(code)}"

    for {module, _} <- :code.all_loaded(),
        name = Atom.to_string(module),
        String.starts_with?(name, "Elixir.Brando.DynamicTemplate."),
        String.ends_with?(name, suffix),
        do: module
  end

  defp insert(view, module_id, sequence) do
    Phoenix.LiveView.send_update(view.pid, BlockField,
      id: @block_field,
      event: "insert_block",
      sequence: sequence,
      module_id: module_id
    )
  end

  test "blocks of one HEEx module load one module, and each still previews", %{conn: conn, page: page} do
    marker = "heex-bound-#{System.unique_integer([:positive])}"
    # A key no atom holds yet: the editor must compile the template before it
    # builds the assigns, as it does on the first render after a restart.
    key = "headline_#{System.unique_integer([:positive])}"
    code = ~s(<article data-marker="#{marker}">{@#{key}}</article>)

    module =
      Factory.insert(:module,
        code: code,
        type: :heex,
        vars: [%Brando.Content.Var{type: :string, key: key, label: "Headline", value: "Preview value"}]
      )

    {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")

    for sequence <- 0..2 do
      insert(view, module.id, sequence)
      await_selector(view, "article[data-marker='#{marker}']")
      render(view)
    end

    html = render(view)
    assert length(Regex.scan(~r/data-marker="#{marker}"/, html)) == 3
    assert html =~ "Preview value"
    assert [_one] = loaded_for(code)
  end

  test "a local and a shared module of one id do not share an id" do
    assert BrandoAdmin.Components.Form.Block.admin_template_id(:local, 3) !=
             BrandoAdmin.Components.Form.Block.admin_template_id(:shared, 3)
  end
end
