defmodule Kora.Store.Memory do
	alias Kora.Store.Prefix
	@delimiter "×"
	@table :kora_table
	# use Kora.Store

	def init(_args) do
		:ets.new(@table, [
			:ordered_set,
			:public,
			:named_table,
			read_concurrency: true,
			write_concurrency: true,
		])
	end

	def merge(_config, layers) do
		layers
		|> Enum.each(fn {path, value} ->
			joined = Enum.join(path, @delimiter)
			:ets.insert(@table, {joined, value})
		end)
	end

	def delete(_config, layers) do
		layers
		|> Enum.each(fn path ->
			{min, max} = Prefix.range(path, @delimiter, %{})
			min
			|> iterate_keys(max)
			|> Enum.each(fn path -> :ets.delete(@table, path) end)
		end)
	end

	def query_path(_config, path, opts) do
		{min, max} = Prefix.range(path, @delimiter, opts)

		min
		|> iterate_keys(max)
		|> Stream.map(&:ets.lookup(@table, &1))
		|> Stream.map(&List.first/1)
		|> Stream.filter(fn item -> item !== nil end)
		|> Stream.map(fn {path, value} -> {String.split(path, @delimiter), value} end)
	end

	def decoder(input), do: input

	def iterate_keys(min, max) do
		Stream.resource(
			fn -> min end,
			fn key ->
				case :ets.next(@table, key) do
					:"$end_of_table" -> {:halt, nil}
					result when result >= max -> {:halt, nil}
					result -> {[result], result}
				end
			end,
			fn _ -> :skip end
		)
	end

end
