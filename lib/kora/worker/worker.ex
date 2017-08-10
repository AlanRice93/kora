defmodule Kora.Worker do

	defmacro __using__(_opts) do
		quote do
			use GenServer
			alias Kora.UUID

			def start_link(state), do: GenServer.start_link(__MODULE__, [state])
			def start_link(key, args), do: GenServer.start_link(__MODULE__, [key, args])

			def init([state]) do
				state.data
				|> __MODULE__.resume
				|> handle_result(state)
			end

			def init([key, args]) do
				IO.puts("NICE")
				args
				|> __MODULE__.first
				|> handle_result(%{
					key: key,
					args: args,
					data: %{},
				})
			end

			def handle_info(msg, state), do: msg |> __MODULE__.info(state.data) |> handle_result(state)
			def handle_cast(msg, state), do: msg |> __MODULE__.cast(state.data) |> handle_result(state)
			def handle_call(msg, from, state), do: msg |> __MODULE__.call(from, state.data) |> handle_result(state)

			def path(key), do: ["kora:worker", inspect(__MODULE__), key]

			defp handle_result({:stop, :shutdown, next}, state) do
				state.key
				|> path
				|> Kora.delete
				{:stop, :shutdown, state}
			end

			defp handle_result({input, next}, state) do
				state = save_state(state, next)
				{input, state}
			end

			defp handle_result({input, msg, next}, state) do
				state = save_state(state, next)
				{input, msg, state}
			end

			defp save_state(state = %{data: old}, next) when next !== old do
				state = Map.put(state, :data, next)
				state.key
				|> path
				|> Kora.merge(state)
				state
			end

			defp save_state(state, _next), do: state
		end
	end

end

defmodule Kora.Worker.Supervisor do
	use Supervisor
	alias Kora.Dynamic

	def start_link(module) do
		Supervisor.start_link(__MODULE__, [module], name: module)
	end

	def init([module]) do
		result = Supervisor.init([
			Supervisor.child_spec(module, restart: :transient, start: { module, :start_link, []})
		], strategy: :simple_one_for_one)
		Task.start_link(fn ->
			resume(module)
		end)
		result
	end

	def start_child(module, key, args) do
		Supervisor.start_child(module, [key, args])
	end

	def resume_child(module, state = %{key: key}) do
		Supervisor.start_child(module, [state])
	end

	def resume(module) do
		["kora:worker", inspect(module)]
		|> Kora.query_path
		|> Dynamic.default(%{})
		|> Map.values
		|> Enum.each(fn %{ "args" => args, "data" => data, "key" => key } ->
			resume_child(module, %{
				key: key,
				args: args,
				data: Dynamic.atom_keys(data),
			})
		end)
	end
end