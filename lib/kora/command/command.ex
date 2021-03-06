defmodule Kora.Command do
	alias Kora.UUID
	require Logger

	def handle(action, body, version, source, state) do
		case trigger_command({action, body, version}, source, state) do
			{:noreply, data} -> {:noreply, data}
			{response, result, data} ->
				{
					%{
						action: response,
						body: result,
						version: 1,
					},
					data,
				}
		end
	end

	def trigger_command(command, source, state) do
		Kora.Config.commands()
		|> Stream.map(&trigger_command(&1, command, source, state))
		|> Stream.filter(&(&1 !== nil))
		|> Stream.take(1)
		|> Enum.at(0) || {:error, :invalid_command, state}
	end

	defp trigger_command(module, command, source, state) do
		try do
			module.handle_command(command, source, state)
		rescue
			e ->
				:error
				|> Exception.format(e)
				|> Logger.error
				{:error, inspect(e), state}
		catch
			_, e ->
				:throw
				|> Exception.format(e)
				|> Logger.error
				{:error, inspect(e), state}
		end
	end

	def trigger_info(msg, source, state) do
		result =
			Kora.Config.commands()
			|> Stream.map(&(&1.handle_info(msg, source, state)))
			|> Stream.filter(&(&1 !== nil))
			|> Enum.at(0) || {:noreply, state}
		case result do
			{:noreply, _} -> result
			{action, body, data} ->
				{
					%{
						key: UUID.ascending(),
						action: action,
						body: body
					},
					data
				}
		end
	end

	defmacro __using__(_opts) do
		quote do
			@before_compile Kora.Command
		end
	end

	defmacro __before_compile__(_env) do
		quote do
			def handle_command({_action, _body, _version}, _from, state) do
				nil
			end

			def handle_info(msg, _from, state) do
				nil
			end
		end
	end

end
