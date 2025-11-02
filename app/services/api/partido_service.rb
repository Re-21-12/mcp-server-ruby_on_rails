module Api
  class PartidoService < BaseClient
    def list
      get('/api/Partido')
    end

    def get_by_id(id)
      get("/api/Partido/#{id}")
    end

    def resultados
      get('/api/Partido/Resultado')
    end
  end
end