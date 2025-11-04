# app/controllers/rpc_controller.rb
require "json"
require "mcp"

class RpcController < ApplicationController
  # desactivar verificación CSRF solo si está definida (soporta ActionController::API)
  if respond_to?(:skip_before_action)
    if _process_action_callbacks.map(&:filter).include?(:verify_authenticity_token)
      skip_before_action :verify_authenticity_token
    elsif respond_to?(:skip_forgery_protection)
      # Rails >=7 way para desactivar protección por controlador
      skip_forgery_protection
    end
  end

  def handle
    payload = JSON.parse(request.body.read) rescue {}
    method = payload["method"].to_s
    id = payload["id"]

    case method
    when "mcp.chat", "llm.chat"
      params_hash = payload["params"] || {}
      prompt = extract_prompt_from_params(params_hash)
      return render json: jsonrpc_error(id, -32602, "Missing prompt"), status: :bad_request if prompt.blank?

      show_tools = params_hash.key?("show_tools") ? !!params_hash["show_tools"] : false

      begin
        result = LlmService.new.chat(prompt, show_tools: show_tools)
        render json: { jsonrpc: "2.0", id: id, result: result }
      rescue => e
        logger.error "[RPC][LLM] #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}"
        render json: jsonrpc_error(id, -32000, "Server error"), status: :bad_gateway
      end
    else
      render json: jsonrpc_error(id, -32601, "Method not found"), status: :not_found
    end
  rescue JSON::ParserError
    render json: jsonrpc_error(nil, -32700, "Parse error"), status: :bad_request
  end

  private

  def extract_prompt_from_params(params)
    return unless params
    if params.is_a?(Hash)
      return params["prompt"] if params["prompt"].present?
      if params["messages"].is_a?(Array)
        user_msg = params["messages"].reverse.find { |m| m["role"] == "user" } || params["messages"].last
        return user_msg && (user_msg["content"] || user_msg["text"])
      end
    end
    nil
  end

  def jsonrpc_error(id, code, message)
    { jsonrpc: "2.0", id: id, error: { code: code, message: message } }
  end
end
