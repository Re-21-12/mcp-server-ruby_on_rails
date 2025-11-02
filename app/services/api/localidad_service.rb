module Api
  class LocalidadService < BaseClient
    def list
      get('/api/Localidad')
    end

    def get_by_id(id)
      get("/api/Localidad/#{id}")
    end
  end
end