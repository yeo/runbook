require "crynamo"

module Runbook
  module Storage
    class DynamoDB
      def self.init
      end

      def self.client
        config = Crynamo::Configuration.new(
          access_key_id: ENV["AWS_ACCESS_KEY_ID"],
          secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"],
          region: "us-east-2",
          endpoint: ENV["DYNAMODB_URL"] || "http://localhost:8000",
        )

        Crynamo::Client.new(config)
      end
    end
  end
end
