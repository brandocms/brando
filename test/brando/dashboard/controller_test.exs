defmodule Brando.Dashboard.ControllerTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  use Plug.Test
  use RouterHelper

  test "index" do
    conn =
      :get
      |> call("/admin/")
      |> with_user
      |> send_request
      
    assert html_response(conn, 200) =~ "Ahoy, Iggy!"
  end

  test "system_info" do
    File.rm_rf!(Path.join([Brando.config(:log_dir), "supervisord.log"]))
    File.mkdir_p!(Path.join([Brando.config(:log_dir)]))

    conn =
      :get
      |> call("/admin/systeminfo")
      |> with_user
      |> send_request

    resp = html_response(conn, 200)

    assert resp =~ "System information"
    assert resp =~ "File not found"

    File.write!(Path.join([Brando.config(:log_dir), "supervisord.log"]), "Log.")

    conn =
      :get
      |> call("/admin/systeminfo")
      |> with_user
      |> send_request

    resp = html_response(conn, 200)

    assert resp =~ "System information"
    assert resp =~ "Log."

    File.rm_rf!(Path.join([Brando.config(:log_dir), "supervisord.log"]))
  end
end
