defmodule Brando.Plug.SSG do
  @moduledoc false
  def init(_) do
    Application.get_env(:brando, :ssg_run, :normal)
  end

  def call(conn, :html) do
    {:ok, ssg_urls} = Brando.SSG.get_urls()

    Plug.Conn.register_before_send(conn, fn conn ->
      cond do
        conn.request_path in ssg_urls and conn.status == 200 -> write_file(conn)
        conn.request_path in ssg_urls -> write_failed(conn)
        true -> conn
      end
    end)
  end

  def call(conn, :normal), do: conn

  # no need to process further if it's an ssg run and not :html
  def call(conn, _) do
    conn
    |> Plug.Conn.halt()
    |> Plug.Conn.send_resp(200, "")
  end

  defp write_file(conn) do
    root_path = Brando.SSG.get_root_path()
    render_path = Path.join([root_path, conn.request_path])
    render_file = Path.join([render_path, "index.html"])
    File.mkdir_p!(render_path)
    formatted_body = Phoenix.LiveView.HTMLFormatter.format(to_string(conn.resp_body), [])
    File.write!(render_file, formatted_body)
    Mix.shell().info([:green, "* ok 200 writing `#{conn.request_path}` -> `#{render_file}"])
    conn
  end

  defp write_failed(conn) do
    Mix.shell().info([:red, "* failed #{conn.status} `#{conn.request_path}`"])
    conn
  end
end
