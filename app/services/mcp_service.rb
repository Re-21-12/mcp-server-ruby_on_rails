require "faraday"
require "json"

class McpService
  def initialize(client: default_client, api_spec_path: default_api_spec_path)
    @client = client
    @api_spec_path = api_spec_path
  end

  private def default_api_spec_path
    ENV.fetch("API_GATEWAY_OPENAPI_PATH", File.join(__dir__, "../../config/api_gateway_openapi.json"))
  end

  private def load_api_spec
    return @api_spec if defined?(@api_spec) && @api_spec
    if File.exist?(@api_spec_path)
      @api_spec = JSON.parse(File.read(@api_spec_path))
    else
      @api_spec = nil
    end
  end

  private def default_client
    # intenta configuración estándar del SDK si existe
    if defined?(MCP) && MCP.respond_to?(:configure)
      MCP.configure do |c|
        c.api_key = ENV["MCP_API_KEY"] if ENV["MCP_API_KEY"]
        c.base_url = ENV["MCP_BASE_URL"] if ENV["MCP_BASE_URL"]
      end
      return MCP.respond_to?(:client) ? MCP.client : (MCP.const_defined?(:Client) ? MCP::Client.new(api_key: ENV["MCP_API_KEY"], base_url: ENV["MCP_BASE_URL"]) : nil)
    end

    if defined?(MCP) && MCP.const_defined?(:Client)
      MCP::Client.new(api_key: ENV["MCP_API_KEY"], base_url: ENV["MCP_BASE_URL"])
    else
      defined?(MCP_CLIENT) ? MCP_CLIENT : raise("MCP client no configurado")
    end
  rescue => e
    raise "Error inicializando cliente MCP: #{e.class} #{e.message}"
  end

  public def call_model(payload)
    # mantiene compatibilidad con llamadas directas simples
    if @client.respond_to?(:call)
      @client.call(payload)
    elsif @client.respond_to?(:post)
      @client.post("/v1/call", payload)
    else
      raise "Método de llamada no disponible en el cliente MCP"
    end
  end

  # Devuelve una lista simple de tools registradas en el cliente MCP (si es posible).
  # Cada entry intenta contener al menos el nombre y un tipo/desc corta.
  public def registered_tools
    return [] unless @client

    tools = []
    if @client.respond_to?(:tools)
      client_tools = @client.tools
      if client_tools.respond_to?(:map)
        tools = client_tools.map do |t|
          if t.respond_to?(:name)
            { name: t.name, type: (t.respond_to?(:type) ? t.type : nil), raw: t }
          elsif t.is_a?(Hash)
            { name: t[:name] || t["name"], type: t[:type] || t["type"], raw: t }
          else
            { name: t.to_s, raw: t }
          end
        end
      else
        tools = [ { name: client_tools.to_s, raw: client_tools } ]
      end
    elsif @client.respond_to?(:registered_tools)
      # algunos SDKs pueden exponer un helper
      tools = @client.registered_tools
    end

    tools
  rescue => _e
    []
  end

  # Llama directamente al API Gateway usando Faraday.
  public def call_api_gateway(method, path, payload: nil, extra_headers: {})
    base = ENV.fetch("API_GATEWAY_URL", "https://api.corazondeseda.lat")
    conn = Faraday.new(url: base) do |f|
      f.request :json
      f.response :raise_error
      f.adapter Faraday.default_adapter
    end

    headers = { "Content-Type" => "application/json" }.merge(extra_headers)
    headers["Authorization"] ||= "Bearer #{ENV['API_GATEWAY_TOKEN']}" if ENV["API_GATEWAY_TOKEN"]

    response = conn.public_send(method) do |req|
      req.url path
      req.headers.update(headers)
      req.body = payload.to_json unless payload.nil?
    end

    begin
      JSON.parse(response.body)
    rescue JSON::ParserError
      response.body
    end
  rescue Faraday::Error => e
    raise "API Gateway request failed: #{e.class} #{e.message}"
  end

  # Intenta registrar la spec OpenAPI en el cliente SDK (si soporta herramientas)
  private def register_openapi_tool
    return unless @client

    # --- cargar spec OpenAPI y registrarla como herramienta 'api_gateway' ---
    load_api_spec
    if @api_spec
      tool = { name: "api_gateway", type: "openapi", spec: @api_spec }

      if @client.respond_to?(:register_tool)
        safe_register(@client, tool)
      elsif @client.respond_to?(:add_tool)
        begin
          @client.add_tool(tool[:name], tool)
        rescue ArgumentError
          @client.add_tool(tool)
        end
      elsif @client.respond_to?(:tools) && @client.tools.respond_to?(:<<)
        @client.tools << tool
      end
    end

    # --- registrar wrappers para los servicios en app/services/api como tools ---
    begin
      # cargar archivos de servicios para autoload en dev
      api_services_dir = File.join(Rails.root, "app", "services", "api", "**", "*_service.rb")
      Dir[api_services_dir].sort.each { |f| require_dependency f } if defined?(Rails)

      # iterar constantes bajo el módulo Api
      if defined?(Api)
        Api.constants.each do |const|
          klass = Api.const_get(const) rescue nil
          next unless klass.is_a?(Class)
          # tomar métodos públicos definidos en la clase (no heredados)
          methods = klass.public_instance_methods(false)
          methods.each do |m|
            # saltar métodos de inicialización u otros no deseados
            next if m.to_s.start_with?("_")
            begin
              require_dependency Rails.root.join("app", "services", "tools", "api_service_tool.rb") if defined?(Rails)
              tool_instance = Tools::ApiServiceTool.new(klass, m)
              if @client.respond_to?(:register_tool)
                safe_register(@client, tool_instance)
              elsif @client.respond_to?(:add_tool)
                begin
                  @client.add_tool(tool_instance.name, tool_instance)
                rescue ArgumentError
                  @client.add_tool(tool_instance)
                end
              elsif @client.respond_to?(:tools) && @client.tools.respond_to?(:<<)
                @client.tools << tool_instance
              end
            rescue => _e
              # no bloquear registro de otras herramientas
              next
            end
          end
        end
      end
    rescue => _e
      # no bloquear startup
      nil
    end
  end

  # helper para manejar firmas distintas de register_tool
  private def safe_register(client, tool)
    # si register_tool acepta 1 arg, pasar tool; si acepta 2, pasar name + tool
    arity = client.method(:register_tool).arity rescue 1
    if arity == 1
      client.register_tool(tool)
    else
      name = tool.respond_to?(:name) ? tool.name : (tool[:name] || "tool")
      client.register_tool(name, tool)
    end
  end

  # Intenta varios métodos comunes del SDK para invocar una acción.
  private def call_via_sdk(call_body)
    return nil unless @client
    candidates = [ :call, :invoke, :request, :predict, :chat, :complete, :create, :execute ]

    candidates.each do |m|
      next unless @client.respond_to?(m)
      begin
        # intento pasar el body entero
        return @client.public_send(m, call_body)
      rescue ArgumentError
        # algunos métodos pueden aceptar (input, options)
        begin
          return @client.public_send(m, call_body[:input], call_body)
        rescue => _
          # ignorar y probar siguiente
        end
      rescue => _
        # ignorar y probar siguiente
      end
    end
    nil
  end

  # options:
  #   :model_input -> texto para el modelo
  #   :endpoint -> ruta relativa (ej. "/api/Jugador")
  #   :method -> :get/:post etc.
  #   :payload -> cuerpo JSON opcional
  public def call_model_and_invoke_api(options = {})
    load_api_spec
    endpoint = options.fetch(:endpoint)
    method = options.fetch(:method, :get)
    payload = options[:payload]
    model_input = options[:model_input] || ""

    # intenta registrar herramienta OpenAPI en el SDK
    register_openapi_tool

    # Construye un cuerpo genérico esperado por muchos SDKs con herramientas
    call_body = {
      input: model_input,
      tool: "api_gateway",
      action: {
        path: endpoint,
        method: method.to_s.upcase,
        payload: payload
      }
    }

    # intenta invocar vía SDK usando varios nombres/métodos
    result = call_via_sdk(call_body)
    return result if result

    # fallback directo por HTTP
    call_api_gateway(method, endpoint, payload: payload)
  end
end
