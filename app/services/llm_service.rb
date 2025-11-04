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

  # options: { show_tools: true } -> when provider=="mcp" returns { result: ..., tools: [...] }
  def chat(prompt, options = {})
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

        # log de tools registradas (útil para debugging)
        begin
          tools = mcp.registered_tools rescue []
          logger = defined?(Rails) && Rails.respond_to?(:logger) ? Rails.logger : nil
          logger.info("[LLM][MCP] registered tools: #{tools.map { |t| t[:name] rescue t }.inspect}") if logger
        rescue => _e
          # no bloquear por logging
        end

        payload = { model: @model, messages: messages }
        res = mcp.call_model(payload)

        # Normalizar respuestas comunes (estilo OpenAI/OpenRouter o SDK)
        final = if res.is_a?(Hash)
          # OpenRouter/OpenAI style
          res.dig("choices", 0, "message", "content") || res.dig("message", "content") || res
        else
          res
        end

        # si el caller pidió ver las tools, devolvemos ambas cosas
        return options[:show_tools] ? { result: final, tools: (tools || []) } : final
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

        # Si se solicita incluir tools (formato OpenRouter/OpenAI function-calling),
        # obtenemos las tools registradas desde McpService y las mapeamos.
        body = { model: @model, messages: messages }
        if options[:include_tools]
          begin
            mcp = McpService.new
            reg = mcp.registered_tools || []
            functions = reg.map do |t|
              raw = t[:raw] rescue nil
              name = t[:name] || (raw.respond_to?(:name) ? raw.name : raw.to_s)
              description = (raw.respond_to?(:description) ? raw.description : t[:description]) || ""
              # parameters: intentar obtener la estructura esperada por OpenAI-like tools
              params = if raw && raw.respond_to?(:parameters)
                # ApiServiceTool#parameters devuelve algo como { params: { type: 'object', ... } }
                p = raw.parameters
                # si tiene key :params, usar ese objeto; si ya tiene la forma, usar tal cual
                p.is_a?(Hash) ? (p[:params] || p["params"] || p) : {}
              else
                {}
              end

              {
                type: "function",
                function: {
                  name: name,
                  description: description,
                  parameters: params
                }
              }
            end

            body[:tools] = functions unless functions.empty?
          rescue => _e
            # no bloquear si algo falla al obtener tools
          end
        end

        req.body = body.to_json
        [ uri, req ]
      else
        raise "OLLAMA_URL no configurada" unless @url.present?
        uri = URI("#{@url}/api/chat")
        req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
        req.body = { model: @model, messages: messages, stream: false }.to_json
        [ uri, req ]
      end

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(req) }

      parsed = parse_response(res)

      # Detectar function_call y ejecutarla localmente si es posible
      begin
        function_call = extract_function_call(parsed)
        if function_call && function_call_retry_limit > 0
          function_call_retry_limit -= 1

          # ejecutar la tool localmente vía McpService/tools
          tool_result = execute_registered_tool(function_call)

          # si se obtuvo un resultado, reintentar llamada al modelo incluyendo el resultado
          if tool_result
            # añadir mensaje de tipo function con el resultado para que el modelo lo vea
            messages << { role: "function", name: function_call_name(function_call), content: tool_result.is_a?(String) ? tool_result : tool_result.to_json }

            # rearmar payload y llamar al modelo de nuevo (si usamos OpenRouter u Ollama)
            if openrouter?
              # reconstruir body con messages y sin stream
              uri = URI(ENV["OPENROUTER_URL"] || "https://openrouter.ai/api/v1/chat/completions")
              req = Net::HTTP::Post.new(uri)
              req["Content-Type"] = "application/json"
              req["Authorization"] = "Bearer #{ENV['OPENROUTER_API_KEY']}"
              req.body = { model: @model, messages: messages }.to_json
              res2 = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(req) }
              return parse_response(res2)
            else
              uri = URI("#{@url}/api/chat")
              req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
              req.body = { model: @model, messages: messages, stream: false }.to_json
              res2 = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(req) }
              return parse_response(res2)
            end
          end
        end
      rescue => _e
        # si falla la ejecución de la tool, seguimos con la respuesta original
      end

      parsed
  end

    # Extrae el nombre del function_call (si la estructura varía entre providers)
    def function_call_name(function_call)
      function_call["name"] || function_call.dig("function", "name")
    end

    # Extrae el objeto function_call desde la respuesta parseada (soporta variantes)
    def extract_function_call(parsed)
      return nil unless parsed.is_a?(Hash)
      fc = parsed.dig("choices", 0, "message", "function_call") || parsed.dig("choices", 0, "function_call")
      return fc if fc
      # Algunas implementaciones devuelven `message` con a assistant.function_call
      nil
    end

    # Ejecuta una tool ya registrada en McpService (busca por nombre y llama #call)
    def execute_registered_tool(function_call)
      name = function_call_name(function_call)
      return nil unless name

      args_raw = function_call["arguments"] || function_call.dig("function", "arguments")
      args = {}
      if args_raw.is_a?(String)
        begin
          args = JSON.parse(args_raw)
        rescue JSON::ParserError
          args = { raw: args_raw }
        end
      elsif args_raw.is_a?(Hash)
        args = args_raw
      end

      mcp = McpService.new
      tools = mcp.registered_tools || []
      found = tools.find { |t| t[:name].to_s == name }
      if found && found[:raw] && found[:raw].respond_to?(:call)
        return found[:raw].call(args)
      end

      # fallback: si no encontramos tool en registered_tools, intentar inferir endpoint
      # por now no implementado
      nil
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
