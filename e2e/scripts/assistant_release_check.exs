# Checks that a production release runs the content assistant's tools
# in-process, with no MCP URL, route, listener or transport: the endpoint does
# not serve, the remote MCP endpoint is off and BrandoMCP is not in the
# release. The model is a scripted client in this file, so nothing leaves the
# machine and no key is needed. It writes to the database it is given, so give
# it an empty one:
#
#   cd e2e
#   MIX_ENV=prod mix deps.get --only prod && MIX_ENV=prod mix release --overwrite
#   createdb assistant_release_check
#   BRANDO_DB_URL=postgres://postgres:postgres@localhost/assistant_release_check \
#   BRANDO_SECRET_KEY_BASE=$(head -c 64 /dev/urandom | base64) \
#     _build/prod/rel/e2e_project/bin/e2e_project eval 'Code.eval_file("scripts/assistant_release_check.exs")'
#   dropdb assistant_release_check

defmodule ReleaseCheck.Model do
  @moduledoc false
  # Answers like a model: list the content types, prepare a proposal that
  # creates a page, then reply in text.
  def generate_text(model, %ReqLLM.Context{messages: messages} = context, opts) do
    results = Enum.count(messages, &(&1.role == :tool))
    send(:release_check, {:model_call, results, Keyword.keys(opts)})

    reply =
      case results do
        0 ->
          %{"tool_calls" => [%{"id" => "c0", "name" => "list_content_types", "arguments" => %{}}]}

        1 ->
          %{
            "tool_calls" => [
              %{
                "id" => "c1",
                "name" => "prepare_proposal",
                "arguments" => %{
                  "summary" => "A page from the release check",
                  "operations" => [
                    %{
                      "op" => "create_entry",
                      "content_type" => "Brando.Pages.Page",
                      "ref" => "release",
                      "fields" => %{
                        "title" => "Release check",
                        "uri" => "release-check",
                        "language" => "en",
                        "template" => "default.html"
                      }
                    }
                  ]
                }
              }
            ]
          }

        _ ->
          %{"text" => "I prepared a draft page for your review."}
      end

    Brando.AI.Cassette.Response.load(
      Map.put(reply, "usage", %{"input_tokens" => 1000, "output_tokens" => 100}),
      model,
      context,
      opts,
      %{}
    )
  end
end

Process.register(self(), :release_check)
check = fn label, true? -> IO.puts("#{if true?, do: "ok  ", else: "FAIL"} #{label}") || (true? || System.halt(1)) end

# The release's own configuration, with the endpoint not serving.
endpoint = Application.get_env(:e2e_project, E2eProjectWeb.Endpoint)
Application.put_env(:e2e_project, E2eProjectWeb.Endpoint, Keyword.put(endpoint, :server, false))

Application.put_env(:brando, Brando.AI,
  enabled: true,
  providers: [anthropic: [api_key: "release-check-not-a-key"]]
)

Application.put_env(:brando, Brando.AI.Agent,
  model: "anthropic:claude-opus-5-5",
  client: ReleaseCheck.Model,
  monthly_token_budget: 1_000_000
)

# The e2e project configures no mail client for prod; the check sends no mail.
Application.put_env(:swoosh, :api_client, false)

{:ok, _, _} = Ecto.Migrator.with_repo(E2eProject.Repo, &Ecto.Migrator.run(&1, :up, all: true, log: false))
{:ok, _} = Application.ensure_all_started(:e2e_project)

IO.puts("Brando #{Application.spec(:brando, :vsn)}, MIX_ENV=prod release, OTP #{System.otp_release()}")
check.("no :brando, Brando.MCP configuration", Application.get_env(:brando, Brando.MCP) in [nil, []])

check.(
  "no brando_mcp application in the release",
  :brando_mcp not in Enum.map(Application.loaded_applications(), &elem(&1, 0))
)

check.("the remote MCP endpoint is off", not Brando.MCP.enabled?(Brando.MCP.tenant(nil, nil)))
check.("the endpoint does not serve", not Phoenix.Endpoint.server?(:e2e_project, E2eProjectWeb.Endpoint))

listening =
  for port <- Port.list(),
      Port.info(port, :name) == {:name, ~c"tcp_inet"},
      {:error, :enotconn} <- [:inet.peername(port)],
      do: port

check.("no listening TCP socket in the VM", listening == [])

user =
  %Brando.Users.User{
    name: "Release Check",
    email: "release-check-#{System.unique_integer([:positive])}@example.com",
    password: Bcrypt.hash_pwd_salt("release-check"),
    role: :superuser,
    language: :en,
    config: %{content_language: :en}
  }
  |> E2eProject.Repo.insert!()

alias Brando.AI.Agent
alias Brando.Content.Proposals

check.("the assistant is available", Agent.available?() and Agent.allowed?(user))
{:ok, conversation} = Agent.start_conversation(user)
{:ok, run} = Agent.send_message(conversation.id, "Make a page called Release check", user, sync: true)

calls = for _ <- 1..3, do: receive(do: ({:model_call, n, keys} -> {n, keys}), after: (0 -> nil))

check.(
  "three model calls, each with the tools and Anthropic's prompt cache",
  match?([{0, _}, {1, _}, {2, _}], calls) and
    Enum.all?(calls, fn {_, keys} -> :tools in keys and :anthropic_prompt_cache in keys end)
)

check.("the run completed in 3 steps", run.status == "completed" and run.steps == 3)
IO.puts("     run: #{run.input_tokens} input + #{run.output_tokens} output tokens counted to the budget")

{:ok, conversation} = Agent.get_conversation(conversation.id, user)
{:ok, proposal} = Proposals.get(conversation.proposal_id, user)

check.(
  "the run prepared proposal version 1 from the Assistant",
  proposal.status == "pending" and proposal.origin == "assistant"
)

tool_messages = for %{role: "tool", tool_name: name} <- Agent.messages(conversation.id, user), do: name

check.(
  "its tools ran in-process: #{Enum.join(tool_messages, ", ")}",
  tool_messages == ~w(list_content_types prepare_proposal)
)

{:ok, _} = Proposals.approve(proposal.id, proposal.version, user)
{:ok, receipt} = Proposals.apply(proposal.id, proposal.version, user)
%{"release" => page_id} = receipt.mappings["created"]
page = E2eProject.Repo.get!(Brando.Pages.Page, page_id)
check.("applying created the page as a draft", page.title == "Release check" and page.status == :draft)
IO.puts("release check passed")
