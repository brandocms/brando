defmodule Brando.Plug.SSG do
  def init(_) do
    Application.get_env(:brando, :ssg_run, :normal)
  end

  def call(conn, :html) do
    {:ok, ssg_urls} = Brando.SSG.get_urls()

    Plug.Conn.register_before_send(conn, fn conn ->
      cond do
        conn.request_path in ssg_urls and conn.status == 200 ->
          root_path = Brando.SSG.get_root_path()
          render_path = Path.join([root_path, conn.request_path])
          render_file = Path.join([render_path, "index.html"])
          File.mkdir_p!(render_path)
          File.write!(render_file, conn.resp_body)
          Mix.shell().info([:green, "* ok 200 writing `#{conn.request_path}` -> `#{render_file}"])
          conn

        conn.request_path in ssg_urls ->
          Mix.shell().info([:red, "* failed #{conn.status} `#{conn.request_path}`"])
          conn

        true ->
          conn
      end
    end)
  end

  def call(conn, :normal) do
    conn
  end

  def call(conn, _) do
    conn |> Plug.Conn.halt() |> Plug.Conn.send_resp(200, "")
  end
end
