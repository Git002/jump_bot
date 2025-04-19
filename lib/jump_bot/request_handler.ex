defmodule JumpBot.RequestHandler do
  require Logger

  @doc """
  Sends a GET request to the GitHub API.
  """
  def get(url, token) do
    headers = [
      {"Authorization", "token #{token}"},
      {"Accept", "application/vnd.github+json"}
    ]

    request = Finch.build(:get, url, headers)

    case Finch.request(request, JumpBot.Finch) do
      result -> handle_response(result, url)
    end
  end

  @doc """
  Sends a POST request to the GitHub API.
  """
  def post(url, body, token) do
    headers = [
      {"Authorization", "token #{token}"},
      {"Content-Type", "application/json"}
    ]

    request = Finch.build(:post, url, headers, Jason.encode!(body))

    case Finch.request(request, JumpBot.Finch) do
      result -> handle_response(result, url)
    end
  end

  @doc false
  defp handle_response({:ok, %Finch.Response{status: status, body: body}}, url)
       when status in [200, 201] do
    case Jason.decode(body) do
      {:ok, json} ->
        # Logger.info("API response json: #{inspect(json)}")
        {:ok, json}

      error ->
        Logger.info("❌ API response body: #{inspect(body)}")
        Logger.error("❌ Failed to decode JSON for #{url}: #{error}")
        {:error, "Invalid JSON in response"}
    end
  end

  defp handle_response({:ok, %Finch.Response{status: status, body: body}}, url) do
    Logger.error("❌ API error [#{status}] at #{url}: body = #{inspect(body)}")

    message =
      case Jason.decode(body) do
        {:ok, %{"message" => msg}} -> msg
        _ -> body
      end

    {:error, "API error (#{status}): #{message}"}
  end

  defp handle_response({:error, reason}, url) do
    Logger.error("❌ HTTP error when calling #{url}: #{inspect(reason)}")
    {:error, "HTTP error: #{reason}"}
  end
end
