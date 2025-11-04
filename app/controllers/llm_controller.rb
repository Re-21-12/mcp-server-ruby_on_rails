class LlmController < ApplicationController
  # desactivar verificación CSRF solo si está definida (soporta ActionController::API)
  if respond_to?(:skip_before_action)
    if _process_action_callbacks.map(&:filter).include?(:verify_authenticity_token)
      skip_before_action :verify_authenticity_token
    elsif respond_to?(:skip_forgery_protection)
      skip_forgery_protection
    end
  end

  # POST /llm/chat
  def chat
  payload = parse_json_request || {}
  prompt = payload["prompt"].to_s
  return render(json: { error: "Missing prompt" }, status: :bad_request) if prompt.blank?

  show_tools = payload.key?("show_tools") ? !!payload["show_tools"] : false

  result = LlmService.new.chat(prompt, show_tools: show_tools)
  render json: result
  rescue => e
    render json: { error: e.message }, status: :bad_gateway
  end

  private

  def parse_json_request
    JSON.parse(request.body.read) rescue {}
  end
end
