defmodule Tesla.Middleware.CurlTest do
  use ExUnit.Case

  import ExUnit.CaptureLog

  def call() do
    Tesla.Middleware.Curl.call(
      %Tesla.Env{
        method: :get,
        url: "https://example.com",
        headers: [{"Content-Type", "application/x-www-form-urlencoded"}],
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
               "curl --GET --header 'Content-Type: application/x-www-form-urlencoded' --data-urlencode 'foo=bar' https://example.com"
    end

    test "is successful" do
      capture_log(fn ->
        assert {:ok, _} = call()
      end)
    end

    test "when body or headers are supplied with redact_fields, redacts those fields" do
      assert capture_log(fn ->
               Tesla.Middleware.Curl.call(
                 %Tesla.Env{
                   method: :get,
                   url: "https://example.com",
                   headers: [
                     {"Authorization", "Bearer 123"},
                     {"Content-Type", "application/x-www-form-urlencoded"}
                   ],
                   body: [{"foo", "bar"}, {"abc", "123"}]
                 },
                 [],
                 redact_fields: ["foo", "authorization"]
               )
             end) =~
               "curl --GET --header 'Authorization: [REDACTED]' --header 'Content-Type: application/x-www-form-urlencoded' --data-urlencode 'foo=[REDACTED]' --data-urlencode 'abc=123' https://example.com"
    end

    test "when env contains query parameters, they are url encoded" do
      assert capture_log(fn ->
               Tesla.Middleware.Curl.call(
                 %Tesla.Env{
                   method: :get,
                   url: "https://example.com",
                   query: [param1: "Hello World", param2: "This is a param with spaces and *special* hars!"],
                 },
                 [],
                 nil
               )
             end) =~
               "curl --GET https://example.comparam1=Hello%20World&param2=This%20is%20a%20param%20with%20spaces%20and%20%2Aspecial%2A%20hars%21"
    end
  end
end
