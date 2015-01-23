defmodule Brando.Auth.AuthController do
  defmacro __using__(_) do
    quote do
      use Phoenix.Controller

      plug :put_layout, @layout
      plug :action

      def login(conn = %Plug.Conn{private: %{plug_session: %{current_user: _}}}, _params) do
        conn
        |> put_flash(:notice, "Du er allerede innlogget.")
        |> redirect(to: "/admin")
      end

      def login(conn, %{"user" => %{"email" => email, "password" => password}}) do
        user = @model.get(email: email)
        case @model.auth?(user, password) do
          true ->   fetch_session(conn)
                    |> put_session(:current_user, user)
                    |> put_flash(:notice, "Innloggingen var vellykket")
                    |> redirect(to: "/admin")
          false ->  conn
                    |> put_flash(:error, "Innloggingen feilet")
                    |> redirect(to: "/login")
        end

      end

      def login(conn, _params) do
        conn
        |> render(:login)
      end

      def logout(conn, _params) do
        conn
        |> Plug.Conn.delete_session(:current_user)
        |> render(:logout)
      end
    end
  end
end
