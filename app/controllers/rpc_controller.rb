# app/controllers/rpc_controller.rb
require 'json'
require 'mcp'

class RpcController < ApplicationController
  skip_before_action :verify_authenticity_token rescue nil

  def handle
    body = request.body.read
    payload = JSON.parse(body) rescue nil

    unless valid_jsonrpc?(payload)
      render json: error_response(nil, -32600, 'Invalid Request'), status: 400 and return
    end

    id     = payload['id']
    method = payload['method']
    params = payload['params'] || {}
    token  = request.headers['Authorization']

    # --- Implementar métodos MCP estándar ---
    case method
    when 'mcp.initialize'
      result = {
        serverInfo: {
          name: 'corazondeseda_mcp',
          version: '1.0.0'
        },
        capabilities: {
          tools: {},
          prompts: {},
          resources: {}
        }
      }

    when 'mcp.list_tools'
      result = [
        { name: 'api_gateway', description: 'Llama endpoints del API Gateway principal' },
        { name: 'partidos.resultados', description: 'Lista resultados de partidos' }
      ]

    when 'mcp.call_tool'
      tool = params['name']
      input = params['arguments'] || {}
      result = call_tool(tool, input, token)

    # --- Métodos JSON-RPC personalizados (compatibilidad legacy) ---
    else
      result = legacy_rpc_call(method, params, token)
    end

    render json: { jsonrpc: '2.0', result: result, id: id }

  rescue => e
    Rails.logger.error e.full_message
    render json: error_response(id, -32000, e.message), status: 500
  end

  private

  def valid_jsonrpc?(payload)
    payload.is_a?(Hash) && payload['jsonrpc'] == '2.0' && payload['method'].is_a?(String)
  end

  def error_response(id, code, message)
    { jsonrpc: '2.0', error: { code: code, message: message }, id: id }
  end

  # --- Integración con tus servicios actuales ---
  def call_tool(name, args, token)
    case name
    when 'partidos.resultados'
      Api::PartidoService.new(token: token).resultados
    when 'jugador.list'
      Api::JugadorService.new(token: token).list
    when 'api_gateway'
      MCPService.new.call_api_gateway(args['method'], args['path'], payload: args['payload'])
    else
      raise "Tool '#{name}' not found"
    end
  end

  def legacy_rpc_call(method, params, token)
    mapping = {
      'partidos.list'       => ->(p){ Api::PartidoService.new(token: token).list },
      'partidos.get'        => ->(p){ Api::PartidoService.new(token: token).get_by_id(p['id']) },
      'jugador.list'        => ->(p){ Api::JugadorService.new(token: token).list }
    }
    handler = mapping[method]
    handler ? handler.call(params) : raise("Method #{method} not found")
  end
end