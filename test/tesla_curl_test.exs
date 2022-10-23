defmodule Tesla.Middleware.CurlTest do
  use ExUnit.Case

  import ExUnit.CaptureLog

  def call() do
    Tesla.Middleware.Curl.call(
      %Tesla.Env{
        method: :get,
        url: "https://example.com",
        headers: [{"Content-Type", "application/json"}],
        body: [{"foo", "bar"}]
      },
      [],
      nil
    )
  end

  describe "call/3" do
    test "formats curl requsts and logs them" do
      assert capture_log(fn ->
               call()
             end) =~
               "curl --GET --header 'Content-Type: application/json' --data-urlencode 'foo=bar' https://example.com"
    end

    test "is successful" do
      capture_log(fn ->
        assert {:ok, _} = call()
      end)
    end
  end
end
