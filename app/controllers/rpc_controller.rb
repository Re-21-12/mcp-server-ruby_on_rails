# app/controllers/rpc_controller.rb
require 'json'
require 'mcp'

class RpcController < ApplicationController
  skip_before_action :verify_authenticity_token

  def handle
    payload = JSON.parse(request.body.read) rescue {}
    method = payload['method'].to_s
    id = payload['id']

    if %w[mcp.chat llm.chat].include?(method)
      prompt = extract_prompt_from_params(payload['params'])
      return render json: jsonrpc_error(id, -32602, 'Missing prompt'), status: :bad_request if prompt.blank?

      result = LlmService.new.chat(prompt)
      render json: { jsonrpc: '2.0', id: id, result: result }
    else
      render json: jsonrpc_error(id, -32601, 'Method not found'), status: :not_found
    end
  rescue JSON::ParserError
    render json: jsonrpc_error(nil, -32700, 'Parse error'), status: :bad_request
  end

  private

  def extract_prompt_from_params(params)
    return unless params
    if params.is_a?(Hash)
      return params['prompt'] if params['prompt'].present?
      if params['messages'].is_a?(Array)
        user_msg = params['messages'].reverse.find { |m| m['role'] == 'user' } || params['messages'].last
        return user_msg && (user_msg['content'] || user_msg['text'])
      end
    end
    nil
  end

  def jsonrpc_error(id, code, message)
    { jsonrpc: '2.0', id: id, error: { code: code, message: message } }
  end
end