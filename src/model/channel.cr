alias Session = Array(HTTP::WebSocket)
class Channel
  @@sessions = {} of String => Session

  def self.subscribe(channel_id, socket)
    # TODO: thread safe
    if @@sessions[channel_id]? == nil
      @@sessions[channel_id] = [] of HTTP::WebSocket
    end

    @@sessions[channel_id] << socket
  end

  def self.unsubscribe(channel_id, socket)
    Channel.sessions[channel_id].delete(socket)
  end

  def self.sessions
    @@sessions
  end
end
