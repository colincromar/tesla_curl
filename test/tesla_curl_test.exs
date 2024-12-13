defmodule Tesla.Middleware.CurlTest do
  use ExUnit.Case

  import ExUnit.CaptureLog

  @base_url "https://example.com"
  @json_headers [{"Authorization", "Bearer 123"}, {"Content-Type", "application/json"}]
  @form_headers [
    {"Authorization", "Bearer 123"},
    {"Content-Type", "application/x-www-form-urlencoded"}
  ]
  @multipart_headers [{"Authorization", "Bearer 123"}, {"Content-Type", "multipart/form-data"}]

  defp build_env(method, url, headers \\ [], body \\ nil, query \\ []) do
    %Tesla.Env{
      method: method,
      url: url,
      headers: headers,
      body: body,
      query: query
    }
  end

  defp call_middleware(env, opts \\ []) do
    Tesla.Middleware.Curl.call(env, [], opts)
  end

  defp assert_curl_log(env, opts, expected_log) do
    assert capture_log(fn -> call_middleware(env, opts) end) =~ expected_log
  end

  defp multipart_body() do
    %Tesla.Multipart{
      parts: [
        %Tesla.Multipart.Part{body: "foo", dispositions: [name: "field1"]},
        %Tesla.Multipart.Part{
          body: "bar",
          dispositions: [name: "field2"],
          headers: [{"content-id", "1"}]
        },
        %Tesla.Multipart.Part{
          body: %File.Stream{path: "test/tesla/tesla_curl_test.exs", modes: [:raw]},
          dispositions: [name: "file", filename: "tesla_curl_test.exs"]
        },
        %Tesla.Multipart.Part{
          body: %File.Stream{path: "test/tesla/test_helper.exs", modes: [:raw]},
          dispositions: [name: "foobar", filename: "test_helper.exs"]
        }
      ]
    }
  end

  describe "call/3" do
    test "is successful" do
      env = build_env(:get, @base_url, @form_headers, [{"foo", "bar"}])
      assert capture_log(fn -> assert {:ok, _} = call_middleware(env) end)
    end

    test "logs error but request succeeds if error occurs" do
      env = build_env(:post, [%{something_invalid: "value"}])
      assert capture_log(fn -> call_middleware(env) end) =~ "[error] ** (ArgumentError)"
    end

    test "redacts specified fields" do
      env = build_env(:get, @base_url, @form_headers, [{"foo", "bar"}])
      opts = [redact_fields: ["foo", "Authorization"]]

      assert_curl_log(
        env,
        opts,
        "curl --header 'Authorization: REDACTED' " <>
          "--header 'Content-Type: application/x-www-form-urlencoded' " <>
          "--data-urlencode 'foo=REDACTED' 'https://example.com'"
      )
    end

    test "handles regex captures in redact_fields" do
      env = build_env(:get, @base_url, [], "<username>some_username</username>")
      opts = [redact_fields: [~r{<username>(.*?)</username>}]]
      assert_curl_log(env, opts, "<username>REDACTED</username>")
    end

    test "handles regex captures in redact_fields for headers and body" do
      env =
        build_env(
          :get,
          @base_url,
          [{"Content-Type", "application/xml"}],
          "<username>some_username</username>"
        )

      opts = [redact_fields: [~r{<username>(.*?)</username>}]]
      assert_curl_log(env, opts, "curl --header 'Content-Type: application/xml'")
    end

    test "encodes query parameters correctly" do
      env = build_env(:get, @base_url, [], nil, param1: "Hello World")
      assert_curl_log(env, [], "param1=Hello%20World")
    end

    test "redacts query parameters correctly" do
      env = build_env(:get, @base_url, [], nil, param1: "Hello World", param2: "Sensitive")
      opts = [redact_fields: ["param2"]]
      assert_curl_log(env, opts, "param2=REDACTED")
    end

    test "handles multipart requests" do
      env = build_env(:post, "#{@base_url}/hello", @multipart_headers, multipart_body())
      assert_curl_log(env, [], "--form 'field1=foo'")
    end

    test "multipart requests redact specified fields" do
      env = build_env(:post, "#{@base_url}/hello", @multipart_headers, multipart_body())
      opts = [redact_fields: ["Authorization"]]
      assert_curl_log(env, opts, "--header 'Authorization: REDACTED'")
    end

    test "compressed flag is handled correctly" do
      env = build_env(:post, @base_url, @json_headers, %{foo: "bar"})
      opts = [compressed: true]
      assert_curl_log(env, opts, "--compressed")
    end

    test "handles follow_redirects option" do
      env = build_env(:get, @base_url)
      opts = [follow_redirects: true]
      assert_curl_log(env, opts, "-L 'https://example.com'")
    end

    test "head and get requests omit -X flag" do
      env_head = build_env(:head, @base_url)
      env_get = build_env(:get, @base_url)
      assert_curl_log(env_head, [], "-I 'https://example.com'")
      assert_curl_log(env_get, [], "curl 'https://example.com'")
    end

    test "body is urlencoded when form headers are supplied" do
      env = build_env(:post, @base_url, @form_headers, "foo=b%20a%20r")
      assert_curl_log(env, [], "--data-urlencode 'foo=b%20a%20r'")
    end

    test "handles nested maps and lists in body" do
      env =
        build_env(:post, @base_url, @json_headers, %{
          "foo" => "bar",
          "nested" => [%{"key" => "value"}, %{"sensitive" => "data"}]
        })

      opts = [redact_fields: ["sensitive"]]
      assert_curl_log(env, opts, "--data 'nested[1][sensitive]=REDACTED'")
    end

    test "handles custom logger levels" do
      env = build_env(:post, @base_url, [], %{foo: "bar"})
      opts = [logger_level: :debug]
      assert_curl_log(env, opts, "[debug] curl -X POST --data 'foo=bar'")
    end

    test "handles multipart with empty query map" do
      env = build_env(:get, @base_url, [], nil, %{})
      assert_curl_log(env, [], "curl 'https://example.com'")
    end
  end
end
