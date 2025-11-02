module Api
  class EquipoService < BaseClient
    def list
      get('/api/Equipo')
    end

    def get_by_id(id)
      get("/api/Equipo/#{id}")
    end

    def paginado(pagina: 1, tamanio: 10)
      get('/api/Equipo/Paginado', { pagina: pagina, tamanio: tamanio })
    end
  end
end