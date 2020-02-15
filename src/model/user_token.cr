class UserToken
  JSON.mapping(
    login: String,
    expired: Int64,
  )

  def get_jwt_token
    jwt_token = Base64.encode(self.to_json)
    signature = OpenSSL::HMAC.hexdigest(:sha1, ENV["SECRET"], jwt_token)

    "#{jwt_token}.#{signature}"
  end

  def to_cookie
    HTTP::Cookie.new(
      name: "user",
      value: get_jwt_token,
      http_only: true,
      secure: ENV["KEMAL_ENV"] == "production"
   )
  end

  def self.from_cookie(cookie : String) : UserToken | Nil
    payload, signature = cookie.split(".")

    if signature != OpenSSL::HMAC.hexdigest(:sha1, ENV["SECRET"], payload)
      return nil
    end

    token = UserToken.from_json(Base64.decode_string(payload))

    if token.expired < Time.utc_now.to_unix
      return nil
    end

    token
  end
end

