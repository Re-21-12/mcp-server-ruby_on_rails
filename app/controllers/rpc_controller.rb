# app/controllers/rpc_controller.rb
require 'jsonrpc2'
begin
  require 'jsonrpc2/server'
rescue LoadError
  Rails.logger.warn "jsonrpc2/server no disponible — comprobando constantes expuestas por la gema"
end
require 'json'

class RpcController < ApplicationController
  # Intentar desactivar CSRF; si no existe el callback, ignorar el error
  begin
    skip_before_action :verify_authenticity_token
  rescue ArgumentError
    Rails.logger.debug "verify_authenticity_token no definido, no se aplica skip_before_action"
  end

  def handle
    body = request.body.read
    payload = JSON.parse(body) rescue nil

    unless payload.is_a?(Hash) && payload['jsonrpc'] == '2.0' && payload['method'].is_a?(String)
      render json: { jsonrpc: '2.0', error: { code: -32600, message: 'Invalid Request' }, id: payload && payload['id'] }, status: 400 and return
    end

    id     = payload['id']
    method = payload['method']
    params = payload['params'] || {}
    token  = request.headers['Authorization']

    methods = {
      'partidos.list'       => ->(p){ Api::PartidoService.new(token: token).list },
      'partidos.get'        => ->(p){ Api::PartidoService.new(token: token).get_by_id(p['id']) },
      'partidos.resultados' => ->(p){ Api::PartidoService.new(token: token).resultados },
      'jugador.list'        => ->(p){ Api::JugadorService.new(token: token).list },
      'jugador.get'         => ->(p){ Api::JugadorService.new(token: token).get_by_id(p['id']) },
      'jugador.by_team'     => ->(p){ Api::JugadorService.new(token: token).by_team(p['id_equipo']) },
      'equipo.list'         => ->(p){ Api::EquipoService.new(token: token).list },
      'equipo.get'          => ->(p){ Api::EquipoService.new(token: token).get_by_id(p['id']) },
      'localidad.list'      => ->(p){ Api::LocalidadService.new(token: token).list },
      'localidad.get'       => ->(p){ Api::LocalidadService.new(token: token).get_by_id(p['id']) }
    }

    handler = methods[method]
    unless handler
      render json: { jsonrpc: '2.0', error: { code: -32601, message: 'Method not found' }, id: id }, status: 404 and return
    end

    result = handler.call(params)
    render json: { jsonrpc: '2.0', result: result, id: id }
  rescue => e
    Rails.logger.error e.full_message
    render json: { jsonrpc: '2.0', error: { code: -32000, message: e.message }, id: (defined?(id) ? id : nil) }, status: 500
  end
end
