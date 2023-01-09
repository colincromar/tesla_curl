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

  def multipart_env() do
    %Tesla.Env{
      method: :post,
      url: "https://example.com/hello",
      query: [],
      headers: [{"Authorization", "Bearer 123"}, {"Content-Type", "multipart/form-data"}],
      body: %Tesla.Multipart{
        parts: [
          %Tesla.Multipart.Part{
            body: "foo",
            dispositions: [name: "field1"],
            headers: []
          },
          %Tesla.Multipart.Part{
            body: "bar",
            dispositions: [name: "field2"],
            headers: [{"content-id", "1"}, {"content-type", "text/plain"}]
          },
          %Tesla.Multipart.Part{
            body: %File.Stream{
              path: "test/tesla/tesla_curl_test.exs",
              modes: [:raw, :read_ahead, :binary],
              line_or_bytes: 2048,
              raw: true
            },
            dispositions: [name: "file", filename: "tesla_curl_test.exs"],
            headers: []
          },
          %Tesla.Multipart.Part{
            body: %File.Stream{
              path: "test/tesla/test_helper.exs",
              modes: [:raw, :read_ahead, :binary],
              line_or_bytes: 2048,
              raw: true
            },
            dispositions: [name: "foobar", filename: "test_helper.exs"],
            headers: []
          }
        ],
        boundary: "4cb14c1c18ef9eb8f141d7d394cb9208",
        content_type_params: ["charset=utf-8"]
      },
      status: nil,
      opts: [],
      __module__: Tesla,
      __client__: %Tesla.Client{
        fun: nil,
        pre: [{Tesla.Middleware.Curl, :call, [[]]}],
        post: [],
        adapter: nil
      }
    }
  end

  describe "call/3" do
    test "formats curl requsts and logs them" do
      assert capture_log(fn ->
               call()
             end) =~
               "curl --header 'Content-Type: application/x-www-form-urlencoded' --data-urlencode 'foo=bar' https://example.com"
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
               "curl --header 'Authorization: [REDACTED]' --header 'Content-Type: application/x-www-form-urlencoded' --data-urlencode 'foo=[REDACTED]' " <>
                 "--data-urlencode 'abc=123' https://example.com"
    end

    test "when env contains query parameters, they are url encoded" do
      assert capture_log(fn ->
               Tesla.Middleware.Curl.call(
                 %Tesla.Env{
                   method: :get,
                   url: "https://example.com",
                   query: [
                     param1: "Hello World",
                     param2: "This is a param with spaces and *special* chars!"
                   ]
                 },
                 [],
                 nil
               )
             end) =~
               "curl https://example.com?param1=Hello%20World&param2=This%20is%20a%20param%20with%20spaces%20and%20%2Aspecial%2A%20chars%21"
    end

    test "multipart requests" do
      assert capture_log(fn ->
               Tesla.Middleware.Curl.call(multipart_env(), [], nil)
             end) =~
               "curl POST --header 'Authorization: Bearer 123' --header 'Content-Type: multipart/form-data' --form field1=foo --form field2=bar " <>
                 "--form file=@test/tesla/tesla_curl_test.exs --form foobar=@test/tesla/test_helper.exs " <>
                 "https://example.com/hello"
    end

    test "multipart with redacted fields" do
      assert capture_log(fn ->
               Tesla.Middleware.Curl.call(multipart_env(), [], redact_fields: ["Authorization"])
             end) =~
               "curl POST --header 'Authorization: [REDACTED]' --header 'Content-Type: multipart/form-data' --form field1=foo --form field2=bar " <>
                 "--form file=@test/tesla/tesla_curl_test.exs --form foobar=@test/tesla/test_helper.exs " <>
                 "https://example.com/hello"
    end

    test "raw request bodies" do
      assert capture_log(fn ->
               Tesla.Middleware.Curl.call(
                 %Tesla.Env{
                   method: :post,
                   url: "https://example.com",
                   headers: [],
                   body: "foo"
                 },
                 [],
                 nil
               )
             end) =~
               "curl POST --data 'foo' https://example.com"
    end

    test "follow_redirects option" do
      assert capture_log(fn ->
               Tesla.Middleware.Curl.call(
                 %Tesla.Env{
                   method: :get,
                   url: "https://example.com",
                   headers: []
                 },
                 [],
                 follow_redirects: true
               )
             end) =~
               "curl -L https://example.com"
    end

    test "head and get requests do not have an -X flag" do
      assert capture_log(fn ->
               Tesla.Middleware.Curl.call(
                 %Tesla.Env{
                   method: :head,
                   url: "https://example.com",
                   headers: []
                 },
                 [],
                 nil
               )
             end) =~
               "curl -I https://example.com"

      assert capture_log(fn ->
               Tesla.Middleware.Curl.call(
                 %Tesla.Env{
                   method: :get,
                   url: "https://example.com",
                   headers: []
                 },
                 [],
                 nil
               )
             end) =~
               "curl https://example.com"
    end

    test "body is urlencoded when content type is application/x-www-form-urlencoded" do
      assert capture_log(fn ->
               Tesla.Middleware.Curl.call(
                 %Tesla.Env{
                   method: :post,
                   url: "https://example.com",
                   headers: [{"Content-Type", "application/x-www-form-urlencoded"}],
                   body: "foo=b a r"
                 },
                 [],
                 nil
               )
             end) =~
               "curl POST --header 'Content-Type: application/x-www-form-urlencoded' --data-urlencode 'foo=b%20a%20r' https://example.com"
    end

    test "handles bodies with nested maps and lists" do
      assert capture_log(fn ->
               Tesla.Middleware.Curl.call(
                 %Tesla.Env{
                   method: :post,
                   url: "https://example.com",
                   headers: [{"Content-Type", "application/json"}],
                   body: %{
                     "foo" => "bar",
                     "baz" => [
                       %{"a" => "b"},
                       %{"c" => "d"},
                       %{"e" => %{"f" => "g"}}
                     ]
                   }
                 },
                 [],
                 nil
               )
             end) =~
               " curl POST --header 'Content-Type: application/json' --data 'baz[0][a]=b' --data 'baz[1][c]=d' --data 'baz[2][e][f]=g' " <>
                "--data 'foo=bar' https://example.com"
    end
  end
end
