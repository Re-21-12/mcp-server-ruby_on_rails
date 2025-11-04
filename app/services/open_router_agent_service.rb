require "net/http"
require "json"

class OpenRouterAgentService
  OPENROUTER_URL = ENV["OPENROUTER_URL"] || "https://openrouter.ai/api/v1/chat/completions"
  MCP_URL = ENV["MCP_URL"] || "http://mcp:3000/rpc"
  API_KEY = ENV["OPENROUTER_API_KEY"]

  def initialize(model: ENV["OPENROUTER_MODEL"] || "mistralai/mixtral-8x7b-instruct")
    raise "OPENROUTER_API_KEY no configurada" unless API_KEY.present?
    @model = model
  end

  ##
  # Envía un prompt al modelo y permite ejecución de herramientas del MCP
  ##
  def chat(prompt)
    messages = [
      { role: "system", content: "Eres un asistente conectado al servidor MCP, capaz de usar herramientas JSON-RPC para obtener datos reales." },
      { role: "user", content: prompt }
    ]
    payload = {
      model: @model,
      messages: messages,
      stream: false,
      tools: available_tools
    }
    response = post_json(OPENROUTER_URL, payload, headers)
    parsed = JSON.parse(response.body)

    # 🚨 1️⃣ Si el modelo devuelve llamadas a herramientas (function calls)
    if parsed.dig("choices", 0, "message", "tool_calls")
      handle_tool_calls(parsed.dig("choices", 0, "message", "tool_calls"))
    else
      parsed.dig("choices", 0, "message", "content") || parsed
    end
  rescue => e
    { error: e.message, backtrace: e.backtrace.take(3) }
  end

    ##
    # Construye dinámicamente el catálogo de herramientas a partir de MCP
    ##
    def available_tools
      begin
        mcp = McpService.new
        regs = mcp.registered_tools || []

        regs.map do |t|
          raw = t[:raw] rescue nil
          name = (t[:name] || t["name"] || (raw.respond_to?(:name) ? raw.name : raw.to_s)).to_s
          description = if raw && raw.respond_to?(:description)
            raw.description
          else
            (t[:description] || t["description"] || "")
          end

          params = {}
          if raw && raw.respond_to?(:parameters)
            p = raw.parameters
            params = p.is_a?(Hash) ? (p[:params] || p["params"] || p) : {}
          elsif t[:parameters] || t["parameters"]
            params = t[:parameters] || t["parameters"]
          end

          params = { "type" => "object" } if params.nil? || params.empty?

          {
            "type" => "function",
            "function" => {
              "name" => name,
              "description" => description,
              "parameters" => params
            }
          }
        end
      rescue => _e
        # fallback mínimo
        [
          {
            "type" => "function",
            "function" => {
              "name" => "partidos.resultados",
              "description" => "Obtiene resultados de partidos desde el MCP Server",
              "parameters" => { "type" => "object", "properties" => { "liga" => { "type" => "string" } }, "required" => [ "liga" ] }
            }
          }
        ]
      end
    end

  ##
  # Ejecuta las herramientas devueltas por el modelo en el MCP
  ##
  def handle_tool_calls(tool_calls)
    results = tool_calls.map do |call|
      function = call.dig("function", "name")
      args = JSON.parse(call.dig("function", "arguments") || "{}")
      result = execute_mcp_tool(function, args)

      {
        name: function,
        args: args,
        result: result
      }
    end

    # Opcionalmente, se puede enviar los resultados de vuelta al modelo para un resumen final:
    follow_up_prompt = "Resumen de resultados obtenidos:\n#{results.to_json}"
    followup_response = post_json(OPENROUTER_URL, {
      model: @model,
      messages: [
        { role: "system", content: "Genera una respuesta legible al usuario en base a los resultados de herramientas previas." },
        { role: "user", content: follow_up_prompt }
      ]
    }, headers)

    parsed_followup = JSON.parse(followup_response.body)
    parsed_followup.dig("choices", 0, "message", "content") || results
  end

  ##
  # Hace la llamada JSON-RPC real al MCP
  ##
  def execute_mcp_tool(method, params)
    payload = {
      jsonrpc: "2.0",
      method: method,
      params: params,
      id: Time.now.to_i
    }
    res = post_json(MCP_URL, payload, { "Content-Type" => "application/json" })
    JSON.parse(res.body)
  rescue => e
    { error: e.message }
  end

  def headers
    {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{API_KEY}"
    }
  end

  def post_json(url, data, headers = {})
    uri = URI(url)
    req = Net::HTTP::Post.new(uri, headers)
    req.body = data.to_json

    Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
      http.request(req)
    end
  end
end
