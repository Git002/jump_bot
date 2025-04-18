defmodule JumpBot.Repo do
  use Ecto.Repo,
    otp_app: :jump_bot,
    adapter: Ecto.Adapters.Postgres
end
