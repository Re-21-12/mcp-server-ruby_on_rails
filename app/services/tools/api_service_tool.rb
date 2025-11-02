module Tools
  class ApiServiceTool
    # service_class: clase (p.ej. Api::PartidoService)
    # method_name: símbolo o string del método a exponer (p.ej. "list" o :get_by_id)
    def initialize(service_class, method_name)
      @service_class = service_class
      @method_name = method_name.to_s
    end

    def name
      "#{service_short_name}.#{@method_name}"
    end

    def description
      "Proxy to #{@service_class.name}##{@method_name}"
    end

    # parámetros genéricos; el modelo/cliente puede enviar un hash 'params'
    def parameters
      { params: { type: "object", description: "Parámetros para #{@service_class.name}##{@method_name}" } }
    end

    # llamada que ejecuta el método del servicio. Se espera params como Hash.
    def call(params = {})
      token = params.delete('_token') || ENV['API_GATEWAY_TOKEN']
      svc = instantiate_service(token: token)

      m = @method_name.to_sym
      if svc.respond_to?(m)
        # intenta pasar hash, luego kwargs, luego sin args
        begin
          return svc.public_send(m, params)
        rescue ArgumentError
          begin
            return svc.public_send(m, **(params || {}))
          rescue ArgumentError
            return svc.public_send(m)
          end
        end
      end

      raise "Método #{m} no disponible en #{@service_class.name}"
    end

    private

    def instantiate_service(token: nil)
      if @service_class.instance_method(:initialize).arity == 0
        @service_class.new
      else
        # intenta inicializar con token si constructor lo acepta
        begin
          @service_class.new(token: token)
        rescue ArgumentError
          @service_class.new
        end
      end
    end

    def service_short_name
      # "api/partido_service" -> "partido" (usa ActiveSupport inflections)
      name = @service_class.name.split('::').last
      name = name.sub(/Service$/, '')
      name.underscore
    end
  end
end