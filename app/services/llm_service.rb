require "net/http"
require "json"

class LlmService
  def initialize(ollama_url = ENV["OLLAMA_URL"], model = ENV["OLLAMA_MODEL"] || "llama3.2:1b")
    @url = ollama_url
    @model = model
  end

  def chat(prompt)
    raise "OLLAMA_URL no configurada" unless @url.present?
    uri = URI("#{@url}/api/generate")
    req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
    req.body = { model: @model, prompt: prompt }.to_json

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
      http.request(req)
    end

    begin
      JSON.parse(res.body)
    rescue JSON::ParserError
      { raw: res.body, status: res.code.to_i }
    end
  end
end
