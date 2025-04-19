defmodule JumpBotWeb.WebhookController do
  use JumpBotWeb, :controller
  require Logger

  alias JumpBot.Users.UserDB
  alias JumpBot.GitHub.{AiHelpers, JWTGen}
  alias JumpBot.RequestHandler

  Dotenv.load!()

  @github_secret System.get_env("GITHUB_SECRET")

  def webhook(conn, params) do
    signature = get_req_header(conn, "x-hub-signature-256") |> List.first()
    event_type = get_req_header(conn, "x-github-event") |> List.first()
    raw_body = conn.assigns[:raw_body]

    Logger.info("Webhook Triggered!")

    cond do
      is_nil(signature) ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Missing signature"})

      raw_body == nil ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Internal error: raw body missing"})

      not valid_signature?(signature, raw_body) ->
        Logger.warning("Invalid Signature")

        conn
        |> put_status(:forbidden)
        |> json(%{error: "Invalid signature"})

      true ->
        Logger.warning("Webhook verified successfully")

        handle_event(event_type, params)

        json(conn, %{message: "Webhook received successfully"})
    end
  end

  defp valid_signature?(header, raw_body) do
    ["sha256", signature] = String.split(header, "=", parts: 2)

    digest =
      :crypto.mac(:hmac, :sha256, @github_secret, raw_body)
      |> Base.encode16(case: :lower)

    Plug.Crypto.secure_compare(digest, signature)
  end

  defp handle_event("installation", %{
         "action" => "created",
         "installation" => %{"id" => id, "account" => %{"login" => login}}
       }) do
    IO.inspect("Handling User Installation.... ")
    UserDB.insert_user(login, to_string(id))
  end

  defp handle_event("pull_request", %{"action" => action} = data)
       when action in ["opened", "synchronize", "reopened"] do
    repo = data["repository"]
    pr = data["pull_request"]
    username = repo["owner"]["login"]
    repo_full_name = repo["full_name"]
    pr_number = data["number"]
    base_sha = pr["base"]["sha"]
    head_sha = pr["head"]["sha"]

    diff_url = "https://api.github.com/repos/#{repo_full_name}/compare/#{base_sha}...#{head_sha}"
    comment_url = "https://api.github.com/repos/#{repo_full_name}/issues/#{pr_number}/comments"

    with {:ok, installation_id} <- fetch_installation_id(username),
         {:ok, access_token} <- fetch_access_token(installation_id),
         {:ok, %{"files" => files}} <- RequestHandler.get(diff_url, access_token) do
      # Get the changes in the code
      code_diff =
        files
        |> Enum.map(fn %{"filename" => filename, "patch" => patch} ->
          %{filename => patch || ""}
        end)

      # Fetch AI rules
      ai_rules = AiHelpers.get_rules(repo_full_name, access_token)

      if map_size(ai_rules) == 0 do
        Logger.info("⚠️ No AI rules found. So not commenting anything...")
        {:ok}
      else
        # Add AI suggestions as comment
        case AiHelpers.generate_ai_response(ai_rules, code_diff) do
          {:ok, ai_text} ->
            case AiHelpers.format_ai_response(ai_text) do
              {:ok, comment_text} ->
                RequestHandler.post(comment_url, %{body: comment_text}, access_token)
                Logger.info("✏️ Comment posted!")

              {:error, reason} ->
                Logger.error("❌ Failed to format AI response: #{inspect(reason)}")
                {:error, reason}
            end

          {:error, reason} ->
            Logger.error("⚠️ AI failed to generate response: #{inspect(reason)}")
        end
      end
    else
      {:error, reason} ->
        Logger.error("❌ GitHub integration failed: #{inspect(reason)}")
    end
  end

  defp handle_event(_, _), do: :ok

  defp fetch_installation_id(username) do
    case UserDB.get_installation_id_by_username(username) do
      nil -> {:error, :installation_id_not_found}
      id -> {:ok, id}
    end
  end

  defp fetch_access_token(installation_id) do
    case JWTGen.generate_github_access_token(installation_id) do
      nil -> {:error, :token_generation_failed}
      token -> {:ok, token}
    end
  end
end
