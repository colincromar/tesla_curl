# TeslaCurl

TeslaCurl is a middleware for [Tesla](https://hex.pm/packages/tesla). It will log a curl command for each request.

This has not officially released yet, but you can use it by adding the following to your `mix.exs` file:

```elixir
def deps do
  [
    {:tesla_curl, git: "https://github.com/colincromar/tesla_curl.git", branch: "main"}
  ]
end
```

## Usage

```elixir
defmodule HelloWorld do
  use Tesla

  plug Tesla.Middleware.Curl
end
```

## Options

#### Field Redaction

You can pass a list of header keys or body field keys to be redacted in the options, like so: 
`redact_fields: ["api_token", "authorization", "password"]`

If supplied, the redacted fields will be replaced with `[REDACTED]` in the curl command.

#### Follow Redirects

If you would like to enable the flag to follow redirects by default, supply `follow_redirects: true` in the options list.

Here is an example of options configuration with all options enabled:


```elixir
plug Tesla.Middleware.Curl, follow_redirects: true, redact_fields: ["api_token", "authorization", "password"]
```

## License

The source code is under the MIT License. Copyright (c) 2022- Colin Cromar.