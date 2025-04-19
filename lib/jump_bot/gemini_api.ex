defmodule JumpBot.GeminiAPI do
  @moduledoc false
  require Logger

  Dotenv.load!()

  @url "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-pro:generateContent"
  @api_key System.get_env("GEMINI_API_KEY")

  if is_nil(@api_key) do
    raise "❌ GEMINI_API_KEY is not set. Please add it to your environment variables."
  end

  @timeout_opts [receive_timeout: 60_000]

  @doc """
  Calls Gemini Pro with a given prompt and returns {:ok, json_string} or {:error, reason}
  """
  def call_model(prompt) when is_binary(prompt) do
    body =
      %{
        contents: [
          %{
            role: "user",
            parts: [%{text: prompt}]
          }
        ],
        tools: [
          %{
            functionDeclarations: [
              %{
                name: "ai_response",
                description: "The AI response containing fixed code suggestions",
                parameters: %{
                  type: "object",
                  required: ["rule_files", "rule", "test_code", "reasoning", "fixed_code"],
                  properties: %{
                    rule_files: %{
                      type: "array",
                      items: %{type: "string"}
                    },
                    rule: %{type: "string"},
                    test_code: %{type: "string"},
                    reasoning: %{type: "string"},
                    fixed_code: %{type: "string"}
                  }
                }
              }
            ]
          }
        ],
        toolConfig: %{
          functionCallingConfig: %{
            mode: "ANY"
          }
        },
        generationConfig: %{
          temperature: 0.3,
          topP: 0.95,
          topK: 40,
          maxOutputTokens: 8192
        }
      }
      |> Jason.encode!()

    url = "#{@url}?key=#{@api_key}"

    headers = [{"Content-Type", "application/json"}]

    request = Finch.build(:post, url, headers, body)

    case Finch.request(request, JumpBot.Finch, @timeout_opts) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        case decode_response_body(body) do
          {:ok,
           %{
             "rule" => _rule,
             "fixed_code" => _fixed_code,
             "rule_files" => _rule_files,
             "reasoning" => _reasoning
           } = ai_response} ->
            {:ok, ai_response}

          {:ok, malformed} ->
            Logger.error("❌ AI response is missing expected keys: #{inspect(malformed)}")
            {:error, "Incomplete function call response"}

          {:error, reason} ->
            Logger.error("⚠️ AI failed to generate response: #{inspect(reason)}")
            {:error, reason}
        end

      {:ok, %Finch.Response{status: status, body: body}} ->
        Logger.error("❌ Unexpected Gemini status: #{status}, body: #{body}")
        {:error, "Unexpected status #{status}"}

      {:error, reason} ->
        Logger.error("❌ Gemini API request failed: #{inspect(reason)}")
        {:error, "Request failed"}
    end
  end

  defp decode_response_body(body) do
    with {:ok, decoded} <- Jason.decode(body),
         %{
           "candidates" => [
             %{
               "content" => %{
                 "parts" => [
                   %{
                     "functionCall" => %{
                       "name" => "ai_response",
                       "args" => args
                     }
                   }
                 ]
               }
             }
           ]
         } <- decoded do
      {:ok, args}
    else
      _ ->
        Logger.error("❌ Failed to parse Gemini response structure: #{body}")
        {:error, "Invalid response format"}
    end
  end
end
