module Api
  class JugadorService < BaseClient
    def list
      get('/api/Jugador')
    end

    def get_by_id(id)
      get("/api/Jugador/#{id}")
    end

    def by_team(id_equipo)
      get("/api/Jugador/byTeam/#{id_equipo}")
    end
  end
end