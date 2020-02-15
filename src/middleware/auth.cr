class AuthHandler < Kemal::Handler
  ALLOWED_USER = ENV["ALLOWED_USER"].split(",").map(&.strip)

  exclude ["/oauth", "/oauth/:provider/callback"]

  get "/oauth" do |env|
    auth_url = "https://github.com/login/oauth/authorize?scope=user,read:org&client_id=#{ENV["GH_CLIENT_ID"]}&state=123&redirect_uri=#{ENV["GH_REDIRECT_URI"]}"
    env.redirect auth_url
  end

  get "/oauth/:provider/callback" do |env|
    code = env.params.query["code"]
    if code.nil?
      halt env, status_code: 403, response: "Forbidden"
    end

    response = HTTP::Client.post("https://github.com/login/oauth/access_token", form:
                                 "client_id=#{ENV["GH_CLIENT_ID"]}&client_secret=#{ENV["GH_CLIENT_SECRET"]}&code=#{code}")

    if response.status_code != 200 || response.body.nil?
      halt env, status_code: 500, response: "Cannot exchange access token"
    end

    access_token = HTTP::Params.parse(response.body)
    current_user = Github::API.new(access_token["access_token"]).me
    if !current_user || current_user.login == ""
      halt env, status_code: 401, response: "Probably the access token is expired"
    end

    unless allow?(current_user.login)
      halt env, status_code: 403, response: "User aren't allowed"
    end

    user_token = UserToken.from_json(%({"login":"#{current_user.login}","expired":#{(Time.utc_now + Time::Span.new(1, 0,0 )).to_unix}}))
    env.response.cookies << user_token.to_cookie

    env.redirect "/"
  end

  def call(ctx)
    return call_next(ctx) if exclude_match?(ctx)

    if user_cookie = ctx.request.cookies["user"]?.try(&.value)
      if user = UserToken.from_cookie(user_cookie)
        if self.class.allow?(user.login)
          return call_next ctx
        end
      end
    end

    ctx.redirect "/oauth"
  end

  def self.allow?(login)
    ALLOWED_USER.includes?(login)
  end
end
