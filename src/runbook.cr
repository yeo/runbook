require "kemal"
require "ecr"
require "markd"
require "json"
require "http/server"
require "http/client"
require "openssl/cipher"
require "openssl/hmac"
require "openssl/sha1"
require "base64"
require "crynamo"

require "./storage/dynamodb"

require "./model/*"
require "./oauth/github"
require "./middleware/auth"

module Runbook
  VERSION = "0.1.0"

  Runbook::Storage::DynamoDB.init

  get "/" do |env|
    current_user = UserToken.from_cookie(env.request.cookies["user"].value)
    books = Book.find_all("./runbook/*.md")

    # TODO: XSS
    render "views/index.ecr", "views/layout.ecr"
  end

  get "/runbook/:id" do |env|
    current_user = UserToken.from_cookie(env.request.cookies["user"].value)

    # TODO: sanitize input to prevent user read any file
    id = env.params.url["id"]
    content = File.read("runbook/" + env.params.url["id"])

    options = Markd::Options.new(time: true)
    document = Markd::Parser.parse(content, options)
    renderer = Markd::RunbookRenderer.new(options)
    lit_code = renderer.render(document)
    #lit_code = Markd.to_html(content)

    render "views/runbook.ecr", "views/layout.ecr"
  end

  get "/logs/:id" do |env|
    current_user = UserToken.from_cookie(env.request.cookies["user"].value)

    id = env.params.url["id"]
    logs = JobLog.latest(id)
    render "views/logs.ecr", "views/layout.ecr"
  end

  ws "/socket" do |socket, ctx|
    channel_id = ctx.params.query["channel"]
    current_user = UserToken.from_cookie(ctx.request.cookies["user"].value)

    unless current_user
      socket.close("Missing access token. Please auth first")
      next
    end

    Channel.subscribe(channel_id, socket)
    log "Channel #{channel_id} has #{Channel.sessions[channel_id].size} clients"

    socket.send(JSON.build do |json|
      json.object do
        json.field "type", "ready"
        json.field "payload", "Welcome, #{current_user.login}. We're ready to receive command"
      end
    end)

    socket.on_message do |message|
      cmd = RunCommand.from_json message

      if cmd.type == "run"
        #https://crystal-lang.org/reference/syntax_and_semantics/if_var.html#limitations
        current_user.try do |u|
          r = JobRunner.new(cmd, channel_id, u)
          r.execute!
        end
      else
        socket.send(JSON.build do |json|
          json.object do
            json.field "type", "info"
            json.field "payload", "Ready to receive command"
          end
        end)
      end
    end

    socket.on_close do
      Channel.unsubscribe(channel_id, socket)
      log "Channel #{channel_id} has #{Channel.sessions[channel_id].size} clients"
    end
  end

  add_handler AuthHandler.new
  Kemal.run
end
