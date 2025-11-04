require "net/http"
require "json"

class LlmService
  AGENTS = {
    "llama" => "meta-llama/llama-3-8b-instruct",
    "mixtral" => "mistralai/mixtral-8x7b-instruct",
    "hermes" => "nousresearch/hermes-2-pro-mistral",
    "phi" => "microsoft/phi-3-mini-4k-instruct"
  }.freeze

  def initialize(
    ollama_url = ENV["OLLAMA_URL"],
    model = ENV["OLLAMA_MODEL"],
    provider: ENV["LLM_PROVIDER"] || nil
  )
    @provider = (provider || ENV["LLM_PROVIDER"]).to_s.downcase.presence
    @provider ||= (ENV["OPENROUTER_API_KEY"].present? ? "openrouter" : "ollama")
    @url = ollama_url
    @model = resolve_model(model)
  end

  def chat(prompt)
    messages = [
      { role: "system", content: "Eres un asistente útil y conciso." },
      { role: "user", content: prompt }
    ]

    # Si el provider es 'mcp', delegamos al McpService para que registre tools
    # y haga la llamada al modelo a través del SDK MCP. Esto permite que el
    # modelo invoque las herramientas registradas (p. ej. Api::PartidoService#resultados).
    if @provider == "mcp"
      begin
        mcp = McpService.new
        # register_openapi_tool es privado; usamos send para forzar registro si es posible.
        begin
          mcp.send(:register_openapi_tool)
        rescue => _e
          # si no se puede registrar no rompemos; seguiremos con la llamada al modelo
        end

        payload = { model: @model, messages: messages }
        res = mcp.call_model(payload)

        # Normalizar respuestas comunes (estilo OpenAI/OpenRouter o SDK)
        if res.is_a?(Hash)
          # OpenRouter/OpenAI style
          return res.dig("choices", 0, "message", "content") || res.dig("message", "content") || res
        end

        return res
      rescue => e
        # si falla el camino MCP, caemos al backend tradicional
        logger = defined?(Rails) && Rails.respond_to?(:logger) ? Rails.logger : nil
        logger.error("[LLM][MCP] fallback: #{e.class}: #{e.message}") if logger
      end
    end

    uri, req =
      if openrouter?
        raise "OPENROUTER_API_KEY no configurada" unless ENV["OPENROUTER_API_KEY"].present?
        uri = URI(ENV["OPENROUTER_URL"] || "https://openrouter.ai/api/v1/chat/completions")
        req = Net::HTTP::Post.new(uri)
        req["Content-Type"] = "application/json"
        req["Authorization"] = "Bearer #{ENV['OPENROUTER_API_KEY']}"
        req.body = { model: @model, messages: messages }.to_json
        [ uri, req ]
      else
        raise "OLLAMA_URL no configurada" unless @url.present?
        uri = URI("#{@url}/api/chat")
        req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
        req.body = { model: @model, messages: messages, stream: false }.to_json
        [ uri, req ]
      end

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(req) }

    parse_response(res)
  end

  private

  def resolve_model(model)
    return model if model.present?

    if openrouter?
      AGENTS[ENV["OPENROUTER_AGENT"].to_s.downcase] || AGENTS["llama"]
    else
      ENV["OLLAMA_MODEL"] || "llama3.2:1b"
    end
  end

  def openrouter?
    @provider == "openrouter"
  end

  def parse_response(res)
    parsed = JSON.parse(res.body)
    if openrouter?
      parsed.dig("choices", 0, "message", "content") || parsed
    else
      parsed.dig("message", "content") || parsed
    end
  rescue JSON::ParserError
    { raw: res.body, status: res.code.to_i }
  end
end
