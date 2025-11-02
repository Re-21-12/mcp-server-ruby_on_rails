require 'faraday'
require 'faraday_middleware'

module Api
  class BaseClient
    def initialize(token: nil, timeout: 5)
      @token = token.presence || KeycloakTokenService.token
      @conn = Faraday.new(url: API_GATEWAY[:base_url]) do |f|
        f.request :json
        f.response :json, content_type: /\bjson$/
        f.options.timeout = timeout
        f.adapter Faraday.default_adapter
      end
    end

    # Métodos HTTP públicos utilizados por los servicios
    def get(path, params = nil)
      resp = @conn.get(path) do |req|
        set_auth(req)
        req.params.update(params) if params && params.is_a?(Hash) && !params.empty?
      end
      handle(resp)
    end

    def post(path, body = nil)
      resp = @conn.post(path) do |req|
        set_auth(req)
        req.body = body if body
      end
      handle(resp)
    end

    def put(path, body = nil)
      resp = @conn.put(path) do |req|
        set_auth(req)
        req.body = body if body
      end
      handle(resp)
    end

    def delete(path, params = nil)
      resp = @conn.delete(path) do |req|
        set_auth(req)
        req.params.update(params) if params && params.is_a?(Hash) && !params.empty?
      end
      handle(resp)
    end

    private

    def set_auth(req)
      return unless @token.present?
      bearer = @token.start_with?('Bearer') ? @token : "Bearer #{@token}"
      req.headers['Authorization'] = bearer
      req.headers['Accept'] = 'application/json'
    end

    def handle(resp)
      return resp.body if resp.success?
      { error: true, status: resp.status, body: resp.body }
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      { error: true, exception: e.class.to_s, message: e.message }
    end
  end
end