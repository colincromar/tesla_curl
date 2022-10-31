defmodule Tesla.Middleware.CurlTest do
  use ExUnit.Case

  alias Tesla.Multipart

  import ExUnit.CaptureLog
  import Tesla.Mock

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
                   query: [param1: "Hello World", param2: "This is a param with spaces and *special* chars!"],
                 },
                 [],
                 nil
               )
             end) =~
               "curl --GET https://example.com?param1=Hello%20World&param2=This%20is%20a%20param%20with%20spaces%20and%20%2Aspecial%2A%20chars%21"
    end
  end

  # describe "multipart" do
  #   setup do
  #     mock(fn
  #       %{method: :get, url: "https://example.com/hello"} ->
  #         %Tesla.Env{status: 200, body: "hello"}

  #       %{method: :post, url: "https://example.com/world"} ->
  #         %Tesla.Env{status: 200, body: "hello"}
  #     end)

  #     :ok
  #   end

  #   def client() do
  #     middleware = [
  #       {Tesla.Middleware.BaseUrl, "https://api.github.com"},
  #       Tesla.Middleware.JSON,
  #       Tesla.Middleware.Curl,
  #     ]

  #     Tesla.client(middleware)
  #   end

    # This test currently just hangs
    # Something tells me that the "--form file=sample file content" isn't working either
    # test "handles multipart requests" do
    #   mp =
    #     Multipart.new()
    #     |> Multipart.add_content_type_param("charset=utf-8")
    #     |> Multipart.add_field("field1", "foo")
    #     |> Multipart.add_field("field2", "bar",
    #       headers: [{"content-id", "1"}, {"content-type", "text/plain"}]
    #     )
    #     |> Multipart.add_file("test/tesla/tesla_curl_test.exs")
    #     |> Multipart.add_file("test/tesla/test_helper.exs", name: "foobar")
    #     |> Multipart.add_file_content("sample file content", "sample.txt")

    #     clnt = client()

    #     assert capture_log(fn ->
    #       Tesla.post(clnt, "https://example.com/world", mp)
    #     end) =~ "curl --POST --header 'Content-Type: multipart/form-data --form field1=foo  --form field2=bar  " <>
    #               <> "--form file=@test/tesla/tesla_curl_test.exs  --form foobar=@test/tesla/test_helper.exs  " <>
    #               "--form file=sample file content https://example.com/world"
    # end
  # end
end
