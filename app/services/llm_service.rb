require "net/http"
require "json"

class LlmService
  def initialize(ollama_url = ENV["OLLAMA_URL"], model = ENV["OLLAMA_MODEL"] || "llama3.2:1b")
    @url = ollama_url
    @model = model
  end

  def chat(prompt)
    raise "OLLAMA_URL no configurada" unless @url.present?

    # Endpoint actualizado
    uri = URI("#{@url}/api/chat")

    # Estructura moderna del request
    body = {
      model: @model,
      messages: [
        { role: "system", content: "Eres un asistente útil y conciso." },
        { role: "user", content: prompt }
      ],
      stream: false # evita respuestas chunked
    }

    req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
    req.body = body.to_json

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
      http.request(req)
    end

    begin
      parsed = JSON.parse(res.body)
      # Extrae solo el contenido generado
      if parsed.is_a?(Hash) && parsed["message"] && parsed["message"]["content"]
        parsed["message"]["content"]
      else
        parsed
      end
    rescue JSON::ParserError
      { raw: res.body, status: res.code.to_i }
    end
  end
end
