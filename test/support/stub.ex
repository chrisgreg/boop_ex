defmodule Boop.TestStub do
  @moduledoc false
  # Helpers for driving Boop against a Req.Test stub instead of a real server.

  import Plug.Conn

  @doc "Config opts that route every request into the `Boop` Req.Test stub."
  def opts(extra \\ []) do
    Keyword.merge(
      [url: "https://boop.test/", api_key: "boop_proj_testkey", req_options: [plug: {Req.Test, Boop}, retry_delay: fn _ -> 0 end]],
      extra
    )
  end

  @doc "Reads the JSON request body from the conn."
  def json_body(conn) do
    {:ok, body, conn} = read_body(conn)
    {Jason.decode!(body), conn}
  end

  def json(conn, status, map) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(map))
  end
end
