class SocketWriter < IO::Memory
  @cmd_id : String
  @channel : String

  def initialize(channel, cmd_id, capacity : Int = 64)
    @channel = channel
    @cmd_id = cmd_id

    super capacity
  end

  def write(slice : Bytes)
    partial_output = String.new(slice)

    Channel.sessions[@channel].each do |socket|
      begin
        socket.send(JSON.build do |json|
          json.object do
            json.field "type", "cmd:partial"
            json.field "stdout", partial_output
            json.field "id", @cmd_id
            json.field "rc", "0"
          end
        end)
      rescue
        # Maybe socket is closed
      end
    end

    super slice
  end
end
