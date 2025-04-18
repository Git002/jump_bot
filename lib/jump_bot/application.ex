defmodule JumpBot.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      JumpBotWeb.Telemetry,
      JumpBot.Repo,
      {DNSCluster, query: Application.get_env(:jump_bot, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: JumpBot.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: JumpBot.Finch},
      # Start a worker by calling: JumpBot.Worker.start_link(arg)
      # {JumpBot.Worker, arg},
      # Start to serve requests, typically the last entry
      JumpBotWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: JumpBot.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    JumpBotWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
