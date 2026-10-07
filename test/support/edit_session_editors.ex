defmodule Brando.EditSessionEditors do
  @moduledoc """
  What two editors in one entry's edit session do, through real LiveViews
  (`Brando.LiveCase`): type in a block's text, read it back, and wait for
  the other editor to catch up.
  """

  import ExUnit.Assertions, only: [flunk: 1]
  import Phoenix.LiveViewTest, only: [element: 2, render: 1, render_change: 2]

  alias Brando.Pages.Page
  alias Brando.Repo

  @text ["entry_block", "block", "refs", "0", "data", "data", "text"]

  @doc "The text ref's path in a block form's params."
  def text_path, do: @text

  @doc "The page's saved entry blocks, read fresh."
  def rows(page) do
    Page
    |> Repo.get!(page.id)
    |> Repo.preload(Brando.Content.BlockPreloads.for_schema(Page), force: true)
    |> Map.get(:entry_blocks)
  end

  @doc """
  A keystroke in a block's text, as the browser sends it: the whole block
  form with the one value changed, targeted at it.
  """
  def type(view, uid, text) do
    selector = "#entry_block_form-#{uid}"

    params =
      view
      |> render()
      |> Brando.LiveCase.form_params(selector)
      |> put_in(@text, text)
      |> Map.put("_target", @text)

    view |> element(selector) |> render_change(params)
  end

  @doc "The text a view shows in a block."
  def shown_text(view, uid),
    do: view |> render() |> Brando.LiveCase.form_params("#entry_block_form-#{uid}") |> get_in(@text)

  @doc "Waits for `fun` to hold, polling every 20 ms."
  def await(fun, tries \\ 150) do
    cond do
      fun.() -> :ok
      tries == 0 -> flunk("condition never held")
      true -> Process.sleep(20) && await(fun, tries - 1)
    end
  end
end
