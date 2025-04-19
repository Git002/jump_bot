defmodule JumpBotWeb.Plugs.RawBodyReader do
  @moduledoc """
  Reads the raw request body, caches it in conn.assigns[:raw_body],
  and returns it so Plug.Parsers can still parse the body.
  """
  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        # Cache the raw body for later (e.g., for signature verification)
        conn = Plug.Conn.assign(conn, :raw_body, body)
        {:ok, body, conn}

      {:more, _partial, _conn} ->
        raise "Request body too large or streaming not supported for webhook parsing"
    end
  end
end
