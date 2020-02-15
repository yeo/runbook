module Github
  class User
    JSON.mapping(
      login: String
    )
  end

  class API
    property token : String

    def initialize(@token)
    end

    def me : Nil | User
      response = HTTP::Client.get("https://api.github.com/user", headers: HTTP::Headers{"Authorization" => "token #{token}"})

      if response.status_code != 200 || response.body.nil?
        return nil
      end

      return User.from_json response.body
    end
  end
end

