- `LiveForm` reads the visitor's address from `X-Forwarded-For` behind a trusted proxy, which the LiveView socket only passes with `:x_headers`, and the lockdown page throttles password attempts only through `Lockdown.password?/2`.
  Add `:x_headers` to the `/live` socket: `websocket: [connect_info: [:peer_data, :x_headers, :user_agent, session: @session_options]]`.
  In `YourWeb.CMS.LockdownController.unlock/2`, replace `Lockdown.password?(password)` with `Lockdown.password?(conn, password)`.
