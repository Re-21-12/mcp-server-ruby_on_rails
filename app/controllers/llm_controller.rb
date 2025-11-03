class LlmController < ApplicationController
  skip_before_action :verify_authenticity_token

  # POST /llm/chat
  def chat
    payload = parse_json_request || {}
    prompt = payload["prompt"].to_s
    return render(json: { error: "Missing prompt" }, status: :bad_request) if prompt.blank?

    result = LlmService.new.chat(prompt)
    render json: result
  rescue => e
    render json: { error: e.message }, status: :bad_gateway
  end

  private

  def parse_json_request
    JSON.parse(request.body.read) rescue {}
  end
end
