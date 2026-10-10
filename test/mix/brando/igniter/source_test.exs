defmodule Mix.Brando.Igniter.SourceTest do
  use ExUnit.Case, async: true

  alias Igniter.Code.Function, as: CodeFunction
  alias Mix.Brando.Igniter.Source

  defp endpoint(body) do
    """
    defmodule StudioWeb.Endpoint do
      use Phoenix.Endpoint, otp_app: :studio
      #{body}
      plug StudioWeb.Router
    end
    """
    |> Sourceror.parse_string!()
    |> Sourceror.Zipper.zip()
    |> Igniter.Code.Module.move_to_defmodule(StudioWeb.Endpoint)
    |> then(fn {:ok, zipper} -> Igniter.Code.Common.move_to_do_block(zipper) end)
    |> then(fn {:ok, zipper} -> zipper end)
  end

  # Whether the endpoint plugs Brando.Plug.Media, as find_call answers it and
  # as Igniter's own alias-expanding comparison alone does.
  defp finds_media?(body) do
    zipper = endpoint(body)
    found? = match?({:ok, _}, Source.find_call(zipper, :plug, [1, 2], Brando.Plug.Media))

    igniter? =
      match?(
        {:ok, _},
        CodeFunction.move_to_function_call_in_current_scope(zipper, :plug, [1, 2], fn call ->
          CodeFunction.argument_equals?(call, 0, Brando.Plug.Media)
        end)
      )

    assert found? == igniter?, body
    found?
  end

  test "a module named through an alias is found, however the alias names it" do
    for body <- [
          "plug Brando.Plug.Media",
          "plug Brando.Plug.Media, at: \"/media\"",
          "alias Brando.Plug\nplug Plug.Media",
          "alias Brando.Plug.Media\nplug Media",
          "alias Brando.Plug.Media, as: Assets\nplug Assets"
        ] do
      assert finds_media?(body), body
    end
  end

  test "a module that only ends or starts the same is another module" do
    for body <- [
          "plug Other.Media",
          "plug Brando.Plug.Media.Extra",
          "plug Brando.Plug.Other",
          "alias Brando.Plug.Media, as: Assets\nplug Assets.Extra",
          "plug :media"
        ] do
      refute finds_media?(body), body
    end
  end
end
