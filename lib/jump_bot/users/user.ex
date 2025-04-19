defmodule JumpBot.Users.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :username, :string
    field :installation_id, :string

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :installation_id])
    |> validate_required([:username, :installation_id])
    |> unique_constraint(:installation_id)
  end
end
