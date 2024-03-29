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
    test "is successful" do
      capture_log(fn ->
        assert {:ok, _} = call()
      end)
    end

    test "logs error, but request still succeeds if error is encountered" do
      # Use a string as method field to simulate a failure
      env = %Tesla.Env{
        method: :post,
        url: [%{something_invalid: "and a value"}],
        headers: [],
        body: nil
      }

      capture_log(fn ->
        assert {:ok, _resp} = Tesla.Middleware.Curl.call(env, [], [])
      end)

      assert capture_log(fn ->
               Tesla.Middleware.Curl.call(env, [], [])
             end) =~
               "[error] ** (ArgumentError) cannot convert the given list to a string."
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
                 redact_fields: ["foo", "Authorization"]
               )
             end) =~
               "[info] curl --header 'Authorization: REDACTED' --header 'Content-Type: application/x-www-form-urlencoded' --data-urlencode 'foo=REDACTED' " <>
                 "--data-urlencode 'abc=123' 'https://example.com'"
    end

    test "handles regex captures in redact_fields for string request bodies" do
      assert capture_log(fn ->
               Tesla.Middleware.Curl.call(
                 %Tesla.Env{
                   method: :get,
                   url: "https://example.com",
                   headers: [],
                   body:
                     "<username>some_username</username><password>some password</password><field1>some field</field1>"
                 },
                 [],
                 redact_fields: [~r{<password>(.*?)</password>}, ~r/<username>(.*?)<\/username>/]
               )
             end) =~
               "[info] curl --data '<username>REDACTED</username><password>REDACTED</password><field1>some field</field1>' 'https://example.com'"
    end

    test "handles regex captures in redact_fields for string request bodies when headers are supplied" do
      assert capture_log(fn ->
               Tesla.Middleware.Curl.call(
                 %Tesla.Env{
                   method: :get,
                   url: "https://example.com",
                   headers: [{"Content-Type", "application/xml"}],
                   body: "<username>some_username</username><password>some password</password>"
                 },
                 [],
                 redact_fields: [~r{<password>(.*?)</password>}]
               )
             end) =~
               "[info] curl --header 'Content-Type: application/xml' --data '<username>some_username</username><password>REDACTED</password>' 'https://example.com'"
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
                 []
               )
             end) =~
               "curl 'https://example.com?param1=Hello%20World&param2=This%20is%20a%20param%20with%20spaces%20and%20%2Aspecial%2A%20chars%21'"
    end

    test "when env contains query parameters in keyword list and redacted fields are specified, fields are redacted," do
      assert capture_log(fn ->
               Tesla.Middleware.Curl.call(
                 %Tesla.Env{
                   method: :get,
                   url: "https://example.com",
                   headers: [{:"User-Agent", "someuseragent"}],
                   query: [
                     param1: "Hello World",
                     param2: "This is a param with spaces and *special* chars!",
                     param3: "This should be redacted"
                   ]
                 },
                 [],
                 redact_fields: [:param1, ~r{param3}, "User-Agent"]
               )
             end) =~
               "[info] curl --header 'User-Agent: REDACTED' 'https://example.com?param1=REDACTED&param2=This%20is%20a%20param%20with%20spaces%20and%20%2Aspecial%2A%20chars%21&param3=REDACTED'"
    end

    test "when env contains query parameters in map and redacted fields are specified, fields are redacted," do
      assert capture_log(fn ->
               Tesla.Middleware.Curl.call(
                 %Tesla.Env{
                   method: :get,
                   url: "https://example.com",
                   query: %{
                     param1: "Hello World",
                     param2: "This is a param with spaces and *special* chars!",
                     param3: "This should be redacted"
                   }
                 },
                 [],
                 redact_fields: [:param1, "param3"]
               )
             end) =~
               "[info] curl 'https://example.com?param1=REDACTED&param2=This%20is%20a%20param%20with%20spaces%20and%20%2Aspecial%2A%20chars%21&param3=REDACTED'"
    end

    test "multipart requests" do
      assert capture_log(fn ->
               Tesla.Middleware.Curl.call(multipart_env(), [], nil)
             end) =~
               "[info] curl -X POST --header 'Authorization: Bearer 123' --header 'Content-Type: multipart/form-data' --form 'field1=foo' --form 'field2=bar' " <>
                 "--form 'file=@test/tesla/tesla_curl_test.exs' --form 'foobar=@test/tesla/test_helper.exs' " <>
                 "'https://example.com/hello'"
    end

    test "multipart with redacted fields" do
      assert capture_log(fn ->
               Tesla.Middleware.Curl.call(multipart_env(), [], redact_fields: ["Authorization"])
             end) =~
               "[info] curl -X POST --header 'Authorization: REDACTED' --header 'Content-Type: multipart/form-data' --form 'field1=foo' --form 'field2=bar' " <>
                 "--form 'file=@test/tesla/tesla_curl_test.exs' --form 'foobar=@test/tesla/test_helper.exs' " <>
                 "'https://example.com/hello'"
    end

    test "string request bodies" do
      assert capture_log(fn ->
               Tesla.Middleware.Curl.call(
                 %Tesla.Env{
                   method: :post,
                   url: "https://example.com",
                   headers: [],
                   body: "foo"
                 },
                 [],
                 []
               )
             end) =~
               "[info] curl -X POST --data 'foo' 'https://example.com'"
    end

    test "map body with atom keys compare safely and are redacted properly" do
      assert capture_log(fn ->
               Tesla.Middleware.Curl.call(
                 %Tesla.Env{
                   method: :post,
                   url: "https://example.com",
                   headers: [],
                   body: %{foo: "bar"}
                 },
                 [],
                 redact_fields: ["foo"]
               )
             end) =~
               "[info] curl -X POST --data 'foo=REDACTED' 'https://example.com'"
    end

    test "redacts fields down the nesting chain if body is a map" do
      assert capture_log(fn ->
               Tesla.Middleware.Curl.call(
                 %Tesla.Env{
                   method: :post,
                   url: "https://example.com",
                   headers: [],
                   body: %{
                     "wiki_page" => %{
                       "name" => "foo",
                       "body" => "bar",
                       "page" => "baz",
                       "options" => %{
                         "is_published" => true,
                         "authorized_editors_ids" => [
                           %{"id" => 1, "editor_name" => "User 1"},
                           %{"id" => 2, "editor_name" => "User 2"}
                         ]
                       }
                     }
                   }
                 },
                 [],
                 redact_fields: ["name", "is_published", "editor_name"]
               )
             end) =~
               "[info] curl -X POST --data 'wiki_page[body]=bar' --data 'wiki_page[name]=REDACTED' " <>
                 "--data 'wiki_page[options][authorized_editors_ids][0][editor_name]=REDACTED' " <>
                 "--data 'wiki_page[options][authorized_editors_ids][0][id]=1' " <>
                 "--data 'wiki_page[options][authorized_editors_ids][1][editor_name]=REDACTED' " <>
                 "--data 'wiki_page[options][authorized_editors_ids][1][id]=2' " <>
                 "--data 'wiki_page[options][is_published]=REDACTED' " <>
                 "--data 'wiki_page[page]=baz' 'https://example.com'"
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
               "[info] curl -L 'https://example.com'"
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
               "[info] curl -I 'https://example.com'"

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
               "[info] curl 'https://example.com'"
    end

    test "body is urlencoded when content type is application/x-www-form-urlencoded" do
      assert capture_log(fn ->
               Tesla.Middleware.Curl.call(
                 %Tesla.Env{
                   method: :post,
                   url: "https://example.com",
                   headers: [{"Content-Type", "application/x-www-form-urlencoded"}],
                   body: "foo=b%20a%20r"
                 },
                 [],
                 []
               )
             end) =~
               "[info] curl -X POST --header 'Content-Type: application/x-www-form-urlencoded' --data-urlencode 'foo=b%20a%20r' 'https://example.com'"
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
                       %{"e" => %{"f" => "g"}},
                       %{"h" => "i"}
                     ]
                   }
                 },
                 [],
                 redact_fields: ["h", "authorization"]
               )
             end) =~
               "[info] curl -X POST --header 'Content-Type: application/json' --data 'baz[0][a]=b' --data 'baz[1][c]=d' " <>
                 "--data 'baz[2][e][f]=g' --data 'baz[3][h]=REDACTED' --data 'foo=bar' 'https://example.com'"
    end

    test "handles compressed flag" do
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
                       %{"e" => %{"f" => "g"}},
                       %{"h" => "i"}
                     ]
                   }
                 },
                 [],
                 redact_fields: ["h", "authorization"],
                 compressed: true
               )
             end) =~
               "[info] curl -X POST --compressed --header 'Content-Type: application/json' --data 'baz[0][a]=b' --data 'baz[1][c]=d' " <>
                 "--data 'baz[2][e][f]=g' --data 'baz[3][h]=REDACTED' --data 'foo=bar' 'https://example.com'"
    end

    test "handles different logger levels" do
      assert capture_log(fn ->
               Tesla.Middleware.Curl.call(
                 %Tesla.Env{
                   method: :post,
                   url: "https://example.com",
                   headers: [],
                   body: %{foo: "bar"}
                 },
                 [],
                 logger_level: :debug
               )
             end) =~
               "[debug] curl -X POST --data 'foo=bar' 'https://example.com'"
    end

    test "redact_fields is atom/string and case agnostic" do
      assert capture_log(fn ->
               Tesla.Middleware.Curl.call(
                 %Tesla.Env{
                   method: :post,
                   url: "https://example.com",
                   headers: [{:Authorization, "some_token"}],
                   body: %{foo: "bar"}
                 },
                 [],
                 # Different cases and types than what is in Tesla.Env
                 redact_fields: ["authorization", "Foo"]
               )
             end) =~
               "[info] curl -X POST --header 'Authorization: REDACTED' --data 'foo=REDACTED' 'https://example.com'"
    end

    test "handles multiple regexes with empty query list" do
      assert capture_log(fn ->
               Tesla.Middleware.Curl.call(
                 %Tesla.Env{
                   method: :get,
                   url: "https://example.com",
                   query: []
                 },
                 [],
                 redact_fields: [~r/<username>(.*?)<\/username>/, ~r/<password>(.*?)<\/password>/]
               )
             end) =~
               "[info] curl 'https://example.com'"
    end

    test "handles multiple regexes with empty query map" do
      assert capture_log(fn ->
               Tesla.Middleware.Curl.call(
                 %Tesla.Env{
                   method: :get,
                   url: "https://example.com",
                   query: %{}
                 },
                 [],
                 redact_fields: [
                   ~r/<username>(.*?)<\/username>/,
                   ~r/<password>(.*?)<\/password>/,
                   "field1"
                 ]
               )
             end) =~
               "[info] curl 'https://example.com'"
    end
  end
end
