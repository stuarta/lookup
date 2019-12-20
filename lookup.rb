require 'rubygems'
require 'bundler/setup'

require 'json'
require 'rack'
require 'rack/oauth2'

require 'net/http'
require 'uri'

require 'logger'

$logger = Logger.new('debug.log')
$logger.level = Logger::DEBUG

class RemoteSSO
  def initialize
    @access_token_expires  = 0
    @refresh_token_expires = 0

    get_client_credentials
    get_oauth_endpoints
    create_client
  end

  def get_client_credentials
    $logger.info("Loading credentials")
    f = File.read('client-credentials.json')
    @sso = JSON.parse(f)
  end

  def get_oauth_endpoints
    $logger.info("Fetching endpoints")
    endpoint_uri = URI(@sso["auth-server-url"] + 'realms/' + @sso["realm"] + '/.well-known/openid-configuration')
    res = Net::HTTP.get_response(endpoint_uri)

    case res
    when Net::HTTPSuccess then
      @endpoints = JSON.parse(res.body)
    else
      print "Error getting endpoints: #{res.code} - #{res.message}\n"
      print "#{res.body}\n"
      exit
    end
    $logger.info("Fetching endpoints complete")
  end

  def create_client
    $logger.info("Creating OAuth2 client")
    Rack::OAuth2.logger = $logger
    @client = Rack::OAuth2::Client.new(
      identifier:             @sso["resource"],
      secret:                 @sso["credentials"]["secret"],
      authorization_endpoint: @endpoints["authorization_endpoint"],
      token_endpoint:         @endpoints["token_endpoint"]
    )
  end

  def token_expired?
    lifetime = @access_token_expires - Time.now().strftime("%s").to_i
    if (lifetime < 10)
      $logger.debug "**Access token has expired"
      true
    else
      false
    end
  end

  def refresh_token_expired?
    lifetime = @refresh_token_expires - Time.now().strftime("%s").to_i
    if (lifetime < 10)
      $logger.debug "Refresh token has expired"
      true
    else
      false
    end
  end

  def log_expiretime
    $logger.debug "Token expires at " + Time.at(@access_token_expires).to_s
    $logger.debug "Refresh token expires at " + Time.at(@refresh_token_expires).to_s
  end

  def update_expiry(access_token)
    @access_token_expires = Time.now().strftime("%s").to_i + access_token.expires_in.to_i
    @refresh_token_expires = Time.now().strftime("%s").to_i + access_token.raw_attributes["refresh_expires_in"].to_i
  end

  def new_token
    access_token = @client.access_token!
    update_expiry(access_token)
    access_token
  end

  def refresh_token
    @client.refresh_token = @access_token.refresh_token
    access_token = @client.access_token!
    update_expiry(access_token)
    access_token
  end

  def access_token!
    if refresh_token_expired?
      # treat as unauthenticated
      @access_token = new_token
      $logger.debug "Created new token"
    elsif token_expired?
      @access_token = refresh_token
      $logger.debug "Refreshed token"
    end
#    log_expiretime
    @access_token
  end

  def user_lookup(query)
    access_token = self.access_token!
    r = access_token.get(@sso["auth-server-url"] + 'admin/realms/' + @sso["realm"] + '/users/' + "?#{query.to_query}")
    j = JSON.parse(r.body)
    key = query.keys[0]
    val = query[key]
    $logger.info "Looked up #{val} by #{key} with #{j.count} result(s)"
    j.each do |u|
      if u[key] == val
        $logger.debug "Found exact match, returning"
        return u.to_json
      end
    end
    $logger.debug "No results match, returning empty result"
    {}.to_json
  end
end

class WebHandler
  def initialize(client)
    @client = client
  end
  def call(env)
    req = Rack::Request.new(env)
    $logger.debug "Received request #{req.params}"
    user = @client.user_lookup(req.params)
    res = Rack::Response.new
    res.set_header('Content-Type', 'application/json')
    res.write(user)
    res.finish
  end
end

client = RemoteSSO.new
wh = WebHandler.new(client)
Rack::Handler::default.run wh
