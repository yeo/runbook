require "base64"
require "markd"

class K8SConfig
  JSON.mapping(
    namespace: String,
    image: String,
    secret: String
  )
end

class JobConfig
  JSON.mapping(
    k8s: K8SConfig?
  )
end

class RunCommand
  JSON.mapping(
    type: String,
    id: String,
    payload: String,
    config: JobConfig?
  )
end

module Markd
  class RunbookRenderer < HTMLRenderer
    def code_block(node : Node, entering : Bool)
      languages = node.fence_language ? node.fence_language.split : nil
      code_tag_attrs = attrs(node)
      pre_tag_attrs = if @options.prettyprint
                        {"class" => "prettyprint"}
                      else
                        nil
                      end

      if languages && languages.size > 0 && (lang = languages[0]) && !lang.empty?
        code_tag_attrs ||= {} of String => String
        code_tag_attrs["class"] = "language-#{lang.strip}"
      end

      cr
      tag("textarea", pre_tag_attrs) do
        #tag("code", code_tag_attrs) do
          out(node.text)
        #end
      end
      cr
    end
  end
end

class ScriptRender
  def initialize(@job_id : String, @k8s : K8SConfig, @script : String)
  end

  ECR.def_to_s "src/scripts/setup.sh"
end

class JobRunner
  property channel : String
  property cmd : RunCommand
  property author : UserToken

  def initialize(@cmd, @channel, @author)
  end

  def execute!()
    script = cmd.payload

    file = File.tempfile("runbook", ".sh") do |file|
      run_in_k8s = false
      cmd.config.try do |config|
        config.k8s.try do |k8s|
          run_in_k8s = true
          # Run in K8S
          render = ScriptRender.new(cmd.id, k8s, script)
          file.print render.to_s
        end
      end

      file.print(script) if !run_in_k8s
    end

    log "Executed file #{file.path}"
    Channel.sessions[channel].each do |socket|
      socket.send(JSON.build do |json|
        json.object do
          json.field "type", "cmd:start"
          json.field "id", cmd.id
          json.field "file", file.path.to_s
        end
      end)
    end

    # output = IO::Memory.new
    output = SocketWriter.new(channel, cmd.id)
    Process.run("/bin/bash", args: [file.path.to_s], output: output, error: output)

    Channel.sessions[channel].each do |socket|
      socket.send(JSON.build do |json|
        json.object do
          json.field "type", "cmd:done"
          json.field "stdout", output.to_s
          json.field "id", cmd.id
          json.field "rc", "0"
        end
      end)
    end

    # TODO: error handle for dynamodb
    file.delete
    r = JobLog.new(
      job: Base64.decode_string(channel),
      runAt: Time.utc_now,
      command: script,
      output: output.to_s,
      author: author.login,
    ).save!
  end
end
