require 'faraday'
require 'json'

class KeycloakTokenService
  TOKEN_CACHE_KEY = 'keycloak:mcp:access_token:v1'.freeze
  MARGIN_SECONDS = 10

  def self.token
    cached = Rails.cache.read(TOKEN_CACHE_KEY)
    return cached if cached.present?

    fetch_and_cache_token
  end

  def self.fetch_and_cache_token
    kc = {
      base: ENV.fetch('KEYCLOAK_BASE_URL', 'https://auth.corazondeseda.lat'),
      realm: ENV.fetch('KEYCLOAK_REALM', 'master'),
      client_id: ENV.fetch('KEYCLOAK_CLIENT_ID', 'mcp-service'),
      client_secret: ENV.fetch('KEYCLOAK_CLIENT_SECRET', 'i3jgwn3hlmhmaXS2kpAywmOkRI1HAfBE')
    }
    raise 'KEYCLOAK_CLIENT_SECRET missing' unless kc[:client_secret]

    conn = Faraday.new(url: kc[:base]) do |f|
      f.request :url_encoded
      f.response :raise_error
      f.adapter Faraday.default_adapter
    end

    resp = conn.post("/realms/#{kc[:realm]}/protocol/openid-connect/token") do |req|
      req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
      req.body = URI.encode_www_form(
        grant_type: 'client_credentials',
        client_id: kc[:client_id],
        client_secret: kc[:client_secret]
      )
    end

    body = JSON.parse(resp.body)
    access_token = body['access_token']
    expires_in = (body['expires_in'] || 300).to_i
    ttl = [expires_in - MARGIN_SECONDS, 5].max
    Rails.cache.write(TOKEN_CACHE_KEY, access_token, expires_in: ttl)
    access_token
  rescue Faraday::ClientError => e
    Rails.logger.error("Keycloak token fetch error: #{e.message}")
    nil
  end
end