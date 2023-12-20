defmodule Flop.Misc do
  @moduledoc false

  @doc """
  Adds wildcard at the specified position(s) of a string for partial matches.
  Escapes `%` and `_` within the given string.

  Options for wildcard placement:
  - :before - Adds wildcard before the string.
  - :after - Adds wildcard after the string.
  - :both - Adds wildcards both before and after the string (default).

      iex> add_wildcard("borscht", :before)
      "%borscht"

      iex> add_wildcard("borscht", :after)
      "borscht%"

      iex> add_wildcard("bor%t", :both)
      "%bor\\\\%t%"

      iex> add_wildcard("bor_cht", :after)
      "bor\\\\_cht%"
  """

  def add_wildcard(value, position \\ :both, escape_char \\ "\\") when is_binary(value) do
    escaped_value = String.replace(value, ["\\", "%", "_"], &"#{escape_char}#{&1}")

    case position do
      :both ->
	"%" <> escaped_value <> "%"
      :before ->
	"%" <> escaped_value
      :after ->
	escaped_value <> "%"
    end
  end

  @doc """
  Splits a search text into tokens.

      iex> split_search_text("borscht batchoy gumbo")
      ["%borscht%", "%batchoy%", "%gumbo%"]
  """
  def split_search_text(s), do: s |> String.split() |> Enum.map(&add_wildcard/1)
end
