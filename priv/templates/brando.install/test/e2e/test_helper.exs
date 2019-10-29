Logger.configure(level: :debug)

{:ok, _} = Application.ensure_all_started(:ex_machina)

Process.sleep(250)
ExUnit.start()

{_, status} =
  System.cmd("sh", ["-c", "cd ../assets/backend; yarn run test"], into: IO.stream(:stdio, :line))

if status > 0 do
  Mix.raise(~s(CYPRESS failed with status #{status}))
end
