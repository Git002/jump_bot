defmodule JumpBot.GitHub.AiHelpers do
  alias JumpBot.RequestHandler
  alias JumpBot.GeminiAPI
  require Logger

  def get_rules(repo, token) do
    url = "https://api.github.com/repos/#{repo}/contents/ai-code-rules"

    with {:ok, file_list} when is_list(file_list) <- RequestHandler.get(url, token) do
      Enum.reduce(file_list, %{}, fn
        %{"type" => "file", "url" => file_url, "name" => name}, acc ->
          case fetch_and_decode_file(file_url, token) do
            {:ok, content} ->
              Map.put(acc, name, content)

            {:error, reason} ->
              Logger.error("❌ Failed to fetch #{name}: #{inspect(reason)}")
              acc
          end

        _, acc ->
          acc
      end)
    else
      {:error, reason} ->
        Logger.error("❌ ai-code-rules folder does not exist: #{inspect(reason)}")
        %{}

      error ->
        Logger.error("⚠️ Unexpected error fetching rules: #{inspect(error)}")
        %{}
    end
  end

  defp fetch_and_decode_file(url, token) do
    with {:ok, %{"content" => encoded}} <- RequestHandler.get(url, token),
         {:ok, decoded} <- Base.decode64(encoded, ignore: :whitespace) do
      {:ok, decoded}
    else
      {:error, reason} ->
        Logger.error("❌ Error: #{inspect(reason)}")
        {:error, reason}

      unexpected ->
        Logger.error("⚠️ Unexpected match: #{inspect(unexpected)}")
        {:error, :invalid_response}
    end
  end

  def generate_ai_response(rules, code) do
    prompt = """
    You will be my AI code review bot that will take git diff as input and will analyze the added lines of code from the diff to see if the newly added changes follow any of the anti-patterns, or rules mentioned that I will provide you along with test code if you think is required or makes sense.

    If you find a line, or lines of code that violate given rules, then show your reasoning by stating why it's a violation and why your fix makes sense along with the fixed code. 'rule_file_name' should be rule file name, for example: "rule01.md" and 'rule' should be summary of the rule extracted from that particular rule_file_name.

    You should include a suggestion on how the developer can change the code to follow the rule with a fix. If the rule or rule file name is not found then output "No suggestions. Everything is alright!". But if the rule is present, then return fixed code as formatted code with proper indentation and the code output should start with ``` backticks then language name (for example: elixir, python, html, css, js, etc) and then end with ``` at last.

    Otherwise, if the rules are present and file is not a .txt or .md type then the code output for fixed_code should be the programming language you identify smartly. For example, below code seems to be elixir code so it should be backticks with elixir as the language name. Type file name then in the next line give the fixed code. Example output is as follows assuming that you identified two file diff and rules apply to both so you give fix for each file if neccessary,

    In file `file_name.ex`:
    ```elixir
    def func(conn, _params) do
        IO.inspect("Hello")
    ```

    In file `account.ex`:
    ```elixir
    def index(conn, _params) do
        IO.inspect("account code")
    ```

    Otherwise if there are multiple files and you think rule applies to only one of them then output only one fixed code, like I this:

    In file `file_name.ex`:
    ```elixir
    def func(conn, _params) do
        IO.inspect("Hello")
    ```

    Now for fixed_code, if no rules are found/matched then in the fixed_code output, just say "Nothing to Fix". No need to output any fixed code, just say "Nothing to Fix". Example output in that case should be:
    {
      "fixed_code": "Nothing to Fix",
      "reasoning" : "Nothing to reason about",
      "test_code" : "No test case needed",
      "rule" : "No rules violated",
      "rule_files" : "No rules applicable"
    }

    Important:
    If no rules are found or applicable for a code scenario when looking at the diff code then always return:
    {
      "fixed_code": "Nothing to Fix",
      "reasoning" : "Nothing to reason about",
      "test_code" : "No test case needed",
      "rule" : "No rules violated",
      "rule_files" : "No rules applicable"
    }

    Otherwise, if rules are found and matched with the code diff situation then output the rule_file_name with applied rule correctly, never leave any output blank.

    Also, if rules are identified, then in the reasoning, always mention what was before in the diff code and after your suggested changes and fixes (if any) what's the situation now. Also explain why this change was necessary if the rule was present. If rule is not present then set reasoning as "Nothing to reason about".

    Note:
    Use formatted text like ** for bold and backticks like ` for any code or filenames.

    Here are the rules data, where each rule is present with their filenames. If below rule is empty or not a match then say "No rules violated" and for rule_file_name say "No rules applicable". Do not ever put rules from your own ever. Apply multiple rules if present and the give combined suggestions in numbered points in markdown.
    Rules = #{inspect(rules)}

    Now here is the diff code, and you can give your output for the below code by categorizing which rule matches the scenario looking at the code:
    #{inspect(code)}

    And lastly, always return values in text. Never return an empty value for rule filenames. If no rule matches or suits a scenario then for filenames simply mention "No rules applicable". Also, when printing out the result value, only return output in bold, code, bullet or numbered points or plain text markdown. Never return any other markdown for rules. Like no h1 , headings or anything else. You can even summarize the rule found that's fine. No need to always return word for word.

    For fixed code or fixed_code output, return the corrected/suggested code. If rule says don't do something, then you have to modify the code to not do that. If the rule suggest to do something, then modify the code to do exactly that. Return the fixed code according to the understanding of the rule.

    Also, return the test case code with backticks and same programming language name if test case makes sense for that code snippet or function. Otherwise return: "No test case needed". Also, apply multiple rules if present and the give combined suggestions in bullet points in markdown. Reasoning could be for multiple files as well. For example:
    - **Overuse of Comments**: In both files index.ex and controller.ex there are lots of unneccessary comments below so I fixed it.
    - **Complex extractions in clauses**: In both files account.ex, and controller.ex, it makes it hard to know which variables are used for pattern/guards and which ones are not.

    The Reason should be any reason you think is applicable to one or multiple files. Write reason category in bold and then the description and for description you can use simple markdown.

    Do the same for Rules as well. Rule name in bold then for description, simple markdown.

    Give reasons as paragraph only if single rule is applied. Just remember, for multiple files code diff changes, there could be multiple code fixes and multiple reasons (if it matches rules, otherwise say not applicable).

    If there are multiple rules applied then you can mention them in bullet points markdown as well with your own summary, you don't need to output exact rules (but dont give examples on your own, just summarize). You can only use bullet points, code backticks and bold markdown for formatting. For example:
    - **Title**: Your explaination
    - **Another Title**: Your explaination
    """

    GeminiAPI.call_model(prompt)
  end

  def format_ai_response(%{
        "fixed_code" => code,
        "reasoning" => reason,
        "test_code" => test_code,
        "rule" => rule,
        "rule_files" => files
      }) do
    rule_list = Enum.map(files, &("- " <> &1)) |> Enum.join("\n")

    formatted_comment = """
    ### ✅ Suggested Code:

    #{code}

    ### 🧠 Reasoning:
    #{reason}

    ### 💣 Test Code:
    #{test_code}

    ### 📜 Rules applied:
    #{rule}

    ### 📁 Rule taken from:
    #{rule_list}
    """

    {:ok, formatted_comment}
  end

  def format_ai_response(resp) do
    IO.inspect(resp, label: "⚠️ Unexpected format in AI response")
    {:error, "❌ Invalid AI response structure"}
  end
end
