require "crynamo"
require "openssl/cipher"
require "openssl/hmac"
require "crypto/subtle"

class JobLog
  property job : String
  property runAt : Time
  property output : String
  property command : String
  property author : String

  @@table = "runbook-dev"

  def initialize(@job, @runAt, @output, @command, @author)
    @@table = "runbook-#{ENV["KEMAL_ENV"]}"
  end

  def self.table : String
    @@table
  end

  def save!
    cipher = OpenSSL::Cipher.new("aes-256-cbc")
    cipher.encrypt
    cipher.key = ENV["SECRET"]
    iv = cipher.random_iv

    encrypted_data = IO::Memory.new
    encrypted_data.write(cipher.update(output))
    encrypted_data.write(cipher.final)
    encrypted_data.write(iv)

    Runbook::Storage::DynamoDB.client.try &.put!(JobLog.table, {
      job: job,
      runAt: runAt.to_unix,
      command: command,
      output: output,
      author: author,
    })
  end

  def self.latest(job : String, day = 1)
    logs = Runbook::Storage::DynamoDB.client.try &.query!(JobLog.table, {
      job: job,
      runAt: AWS::DynamoDB::DDB::KeyConditionExpression(Int64).new(">", 10.to_i64)
    })

    logs.map do |log|
      # Use temp var due to type checker limitation of 0.27
      _runAt = log["runAt"]
      r      = case _runAt
             when Int64, Int32
               Time.unix(_runAt.to_i)
             else
               Time.utc_now
             end

      JobLog.new(
        log["job"].is_a?(String) ? log["job"].to_s : "",
        r,
        log["output"].try &.to_s || "",
        log["command"].try &.to_s || "",
        log["author"].try &.to_s || "",
      )
    end
  end
end
