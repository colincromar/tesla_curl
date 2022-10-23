# TeslaCurl

Tesla Curl is a middleware for [Tesla](https://hex.pm/packages/tesla). It will log a curl command for each request.

This has not officially released yet, but you can use it by adding the following to your `mix.exs` file:

```elixir

## Installation

Add `:tesla_curl` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:tesla_curl, "~> 0.0.1"}
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

## License

The source code is under the MIT License. Copyright (c) 2022- Colin Cromar.