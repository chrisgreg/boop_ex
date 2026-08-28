defmodule Boop.ConfigTest do
  use ExUnit.Case

  alias Boop.Config

  setup do
    env = Application.get_all_env(:boop_ex)
    on_exit(fn ->
      Enum.each(Application.get_all_env(:boop_ex), fn {k, _} -> Application.delete_env(:boop_ex, k) end)
      Enum.each(env, fn {k, v} -> Application.put_env(:boop_ex, k, v) end)
      System.delete_env("BOOP_URL")
      System.delete_env("BOOP_API_KEY")
    end)
  end

  test "defaults" do
    assert %Config{url: nil, api_key: nil, timeout: 10_000, enabled: true, redact_keys: []} = Config.resolve([])
  end

  test "application env, then env vars, then per-call opts" do
    System.put_env("BOOP_URL", "https://env.example/")
    System.put_env("BOOP_API_KEY", "boop_proj_env")
    assert %Config{url: "https://env.example", api_key: "boop_proj_env"} = Config.resolve([])

    Application.put_env(:boop_ex, :url, "https://app.example/")
    Application.put_env(:boop_ex, :source, "uini")
    assert %Config{url: "https://app.example", source: "uini", api_key: "boop_proj_env"} = Config.resolve([])

    assert %Config{url: "https://call.example", timeout: 1, enabled: false} =
             Config.resolve(url: "https://call.example/", timeout: 1, enabled: false)
  end
end
