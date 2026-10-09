defmodule Brando.Deprecated.RenamedModulesTest.LegacyRouter do
  # A site router written before 0.55, naming the public controllers by
  # their old names
  use Phoenix.Router

  get "/sitemaps/:file", Brando.SitemapController, :show
  get "/__p__/:preview_key", Brando.PreviewController, :show
end

defmodule Brando.Deprecated.RenamedModulesTest do
  @moduledoc """
  The modules renamed in 0.55 (#2833) keep working under their old names
  until 0.57, and say so.
  """
  use Brando.LiveCase

  require Phoenix.ChannelTest

  alias Brando.Deprecated.RenamedModules
  alias Brando.Deprecated.RenamedModulesTest.LegacyRouter
  alias Brando.Sites.Preview
  alias Brando.Users
  alias Brando.Users.UserConfig

  # The warnings are logged once per node: forget them around each test
  setup do
    previous = Logger.level()
    Logger.configure(level: :warning)
    forget_warnings()

    on_exit(fn ->
      Logger.configure(level: previous)
      forget_warnings()
    end)
  end

  defp forget_warnings, do: Enum.each(Map.keys(RenamedModules.all()), &:persistent_term.erase({RenamedModules, &1}))

  test "every old name is a loaded shim for a loaded new module" do
    for {old, new} <- RenamedModules.all() do
      assert Code.ensure_loaded?(old), "#{inspect(old)} has no shim"
      assert Code.ensure_loaded?(new), "#{inspect(old)} is renamed to #{inspect(new)}, which does not exist"
      refute old == new
    end
  end

  test "the shims' own functions are deprecated, and name the new module" do
    for {old, new} <- RenamedModules.all(), {{name, arity}, reason} <- old.__info__(:deprecated) do
      # add_sitemap/2 was itself a delegate to Brando.SEO.Robots
      assert reason =~ "Use #{inspect(new)}.#{name}/#{arity} instead" or
               {old, name} == {Brando.SEOController, :add_sitemap},
             "#{inspect(old)}.#{name}/#{arity}: #{reason}"
    end

    assert {:alert, 2} in Enum.map(Brando.UserChannel.__info__(:deprecated), &elem(&1, 0))
  end

  test "the Identity's schemas keep their changesets under the old names" do
    # Picked at runtime: the compiler follows a literal module, even through
    # a variable, and warns that changeset/2 is deprecated
    old = Map.new(RenamedModules.all(), fn {old, new} -> {new, old} end)
    {link, meta} = {old[Brando.Sites.Link], old[Brando.Sites.Meta]}
    changeset = link.changeset(%Brando.Sites.Link{}, %{name: "Instagram", url: "https://x.com"})
    assert changeset.valid?
    assert changeset.data.__struct__ == Brando.Sites.Link

    refute meta.changeset(%Brando.Sites.Meta{}, %{key: "k"}).valid?
    assert Code.ensure_loaded?(Brando.Meta.HTML)
  end

  test "a router that routes to the old controller names still serves them, and warns once" do
    name = "renamed-#{System.unique_integer([:positive])}.xml"
    dir = Path.join(Brando.Tenant.Storage.current_media_root(), "sitemaps")
    File.mkdir_p!(dir)
    path = Path.join(dir, name)
    File.write!(path, "<urlset/>")
    on_exit(fn -> File.rm(path) end)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert %{status: 200, resp_body: "<urlset/>"} = dispatch(:get, "/sitemaps/#{name}")
        assert %{status: 404} = dispatch(:get, "/sitemaps/missing.xml")
      end)

    assert log =~ "Brando.SitemapController is deprecated: renamed to BrandoWeb.SitemapController"
    assert length(String.split(log, "Brando.SitemapController is deprecated")) == 2
  end

  test "a shared preview through the old controller name", %{current_user: user} do
    preview =
      Repo.insert!(%Preview{
        creator_id: user.id,
        preview_key: Ecto.UUID.generate(),
        html: Brando.Utils.term_to_binary("<main>Shared draft</main>"),
        expires_at: DateTime.utc_now() |> DateTime.add(60, :second) |> DateTime.truncate(:second)
      })

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        conn = dispatch(:get, "/__p__/#{preview.preview_key}")
        assert conn.status == 200
        assert conn.resp_body =~ "Shared draft"
        assert conn.private.phoenix_controller == BrandoWeb.PreviewController
      end)

    assert log =~ "Brando.PreviewController is deprecated"
  end

  # As a socket that still registers the old names joins them
  test "the old channel names join and push like the new ones" do
    user = Factory.insert(:random_user, role: :editor, config: %UserConfig{reset_password_on_first_login: false})
    session = Users.generate_user_session_token(user)
    token = Users.build_socket_token(user, Users.token_id(session))
    {:ok, socket} = Phoenix.ChannelTest.connect(BrandoAdmin.AdminSocket, %{"token" => token})

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:ok, _, channel} = Phoenix.ChannelTest.subscribe_and_join(socket, Brando.UserChannel, "user:#{user.id}")
        assert channel.channel == Brando.UserChannel

        # The intercepted events reach the client through the shim's handle_out/3
        BrandoAdmin.UserChannel.alert(user, "Hello")
        Phoenix.ChannelTest.assert_push("alert", %{message: "Hello"})

        assert {:error, %{reason: "forbidden"}} =
                 Phoenix.ChannelTest.subscribe_and_join(socket, Brando.LobbyChannel, "lobby", %{})
      end)

    assert log =~ "Brando.UserChannel is deprecated: renamed to BrandoAdmin.UserChannel"
    assert log =~ "Brando.LobbyChannel is deprecated"
  end

  test "an endpoint rendering errors with Brando.ErrorHTML gets the same pages" do
    assigns = %{conn: Plug.Conn.put_private(build_conn(), :phoenix_endpoint, @endpoint)}

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        for template <- ~w(400 404 406 500) do
          assert Phoenix.Template.render_to_string(Brando.ErrorHTML, template, "html", assigns) ==
                   Phoenix.Template.render_to_string(BrandoWeb.ErrorHTML, template, "html", assigns)
        end
      end)

    assert log =~ "Brando.ErrorHTML is deprecated: renamed to BrandoWeb.ErrorHTML"
  end

  defp dispatch(method, path) do
    method
    |> Phoenix.ConnTest.build_conn(path)
    |> Plug.Conn.assign(:language, "en")
    |> LegacyRouter.call(LegacyRouter.init([]))
  end
end
