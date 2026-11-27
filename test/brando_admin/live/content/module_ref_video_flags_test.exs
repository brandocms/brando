defmodule BrandoAdmin.Live.Content.ModuleRefVideoFlagsTest do
  # The module editor's playback settings on a video ref and a media ref's
  # video template (#4011): Default, On and Off, where Default stores nil
  # and leaves the setting to the video or the template.
  use Brando.LiveCase

  @moduletag :capture_log

  alias Brando.Content.Module
  alias Brando.Repo

  @template_flags ~w(autoplay preload controls loop muted)a

  setup %{current_user: user} do
    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module, %{
          name: %{"en" => "Clip"},
          namespace: %{"en" => "Content"},
          help_text: %{},
          code: "{% ref refs.clip %}{% ref refs.media %}",
          refs: [
            %{name: "clip", uid: Brando.Utils.generate_uid(), data: %{type: "video", data: %{}}},
            %{
              name: "media",
              uid: Brando.Utils.generate_uid(),
              data: %{type: "media", data: %{available_blocks: ["picture", "video"], template_video: %{}}}
            }
          ],
          vars: []
        }),
        user
      )

    %{module: module}
  end

  defp open(conn, module) do
    {:ok, view, _html} = live(conn, "/admin/config/content/modules/update/#{module.id}")
    view
  end

  defp submit(view, params) do
    view |> form("#module_form-el form.main-form") |> render_submit(%{"module" => params})
  end

  defp ref_data(module, name) do
    Module
    |> Repo.get!(module.id)
    |> Repo.preload(:refs)
    |> Map.fetch!(:refs)
    |> Enum.find(&(&1.name == name))
    |> Map.fetch!(:data)
    |> Map.fetch!(:data)
  end

  defp video(module), do: ref_data(module, "clip")
  defp template(module), do: ref_data(module, "media").template_video

  # The ref forms' inputs by name, `refs[0][data][data][preload]` for the clip
  defp flag_name(0, flag), do: "module[refs][0][data][data][#{flag}]"
  defp flag_name(1, flag), do: "module[refs][1][data][data][template_video][#{flag}]"

  defp checked(view, ref, flag) do
    view
    |> element(~s(input[name="#{flag_name(ref, flag)}"][checked]))
    |> render()
    |> then(&Regex.run(~r/value="([^"]*)"/, &1, capture: :all_but_first))
    |> hd()
  end

  defp put_flags(params, ref, flags, value) do
    Enum.reduce(flags, params, fn flag, acc ->
      path = ["refs", "#{ref}", "data", "data"] ++ if(ref == 1, do: ["template_video"], else: []) ++ ["#{flag}"]
      put_in(acc, Enum.map(path, &Access.key(&1, %{})), value)
    end)
  end

  test "a save that leaves the switches alone keeps them unset", %{conn: conn, module: module} do
    submit(open(conn, module), %{"class" => "clip"})

    assert %{class: "clip"} = Repo.get!(Module, module.id)
    assert %{autoplay: nil, preload: nil} = video(module)
    for flag <- @template_flags, do: assert(Map.fetch!(template(module), flag) == nil, "#{flag}")

    view = open(conn, module)
    assert checked(view, 0, :preload) == ""
    for flag <- @template_flags, do: assert(checked(view, 1, flag) == "")
  end

  test "On, Off and Default store true, false and nil, and show again", %{conn: conn, module: module} do
    for {value, stored} <- [{"true", true}, {"false", false}, {"", nil}] do
      params = %{} |> put_flags(0, [:autoplay, :preload], value) |> put_flags(1, @template_flags, value)
      submit(open(conn, module), params)

      assert %{autoplay: ^stored, preload: ^stored} = video(module)
      for flag <- @template_flags, do: assert(Map.fetch!(template(module), flag) == stored, "#{flag} #{value}")

      view = open(conn, module)
      assert checked(view, 0, :preload) == value
      for flag <- @template_flags, do: assert(checked(view, 1, flag) == value)
    end
  end

  test "the video ref keeps the switches it has", %{conn: conn, module: module} do
    view = open(conn, module)

    for flag <- ~w(controls loop muted) do
      refute has_element?(view, ~s([name="#{flag_name(0, flag)}"]))
    end

    # Play button and progress have no unset state: they stay switches
    for ref <- [0, 1], flag <- [:play_button, :progress] do
      assert has_element?(view, ~s(input[type="checkbox"][name="#{flag_name(ref, flag)}"]))
    end
  end

  test "a media ref that offers no video keeps its stored template", %{conn: conn, current_user: user} do
    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module, %{
          name: %{"en" => "Still"},
          namespace: %{"en" => "Content"},
          help_text: %{},
          code: "{% ref refs.media %}",
          refs: [
            %{
              name: "media",
              uid: Brando.Utils.generate_uid(),
              data: %{type: "media", data: %{available_blocks: ["picture"], template_video: %{preload: false, loop: true}}}
            }
          ],
          vars: []
        }),
        user
      )

    view = open(conn, module)
    refute render(view) =~ "[template_video][preload]"
    submit(view, %{"class" => "still"})

    assert %{preload: false, loop: true} = ref_data(module, "media").template_video
  end
end
