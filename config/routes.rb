Rails.application.routes.draw do
  mount Rswag::Ui::Engine => '/api-docs'
  mount Rswag::Api::Engine => '/api-docs'
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
  post '/rpc', to: 'rpc#handle'

  # Defines the root path route ("/")
  # root "posts#index"

  # --- API routes (proxy controllers -> Api::*) ---
  scope '/api' do
    # Partido
    get    '/Partido',                     to: 'api/partidos#index'
    post   '/Partido',                     to: 'api/partidos#create'
    get    '/Partido/Paginado',            to: 'api/partidos#paginado'
    get    '/Partido/Resultado',           to: 'api/partidos#resultados'
    get    '/Partido/:id',                 to: 'api/partidos#show'
    put    '/Partido/:id',                 to: 'api/partidos#update'
    delete '/Partido/:id',                 to: 'api/partidos#destroy'
    get    '/Partido/Reporte/Roster',      to: 'api/partidos#roster'

    # Equipo
    get    '/Equipo',                      to: 'api/equipos#index'
    post   '/Equipo',                      to: 'api/equipos#create'
    get    '/Equipo/Paginado',             to: 'api/equipos#paginado'
    get    '/Equipo/reporte',              to: 'api/equipos#reporte'
    get    '/Equipo/:id',                  to: 'api/equipos#show'
    put    '/Equipo',                      to: 'api/equipos#update' # original openapi usa query id
    patch  '/Equipo',                      to: 'api/equipos#patch'
    delete '/Equipo/:id',                  to: 'api/equipos#destroy'

    # Jugador
    get    '/Jugador',                     to: 'api/jugadores#index'
    post   '/Jugador',                     to: 'api/jugadores#create'
    get    '/Jugador/Paginado',            to: 'api/jugadores#paginado'
    get    '/Jugador/Reporte/Equipo',      to: 'api/jugadores#reporte_equipo'
    get    '/Jugador/Reporte/EstadisticasJugador', to: 'api/jugadores#reporte_estadisticas'
    get    '/Jugador/:id',                 to: 'api/jugadores#show'
    patch  '/Jugador/:id',                 to: 'api/jugadores#patch'
    delete '/Jugador/:id',                 to: 'api/jugadores#destroy'
    get    '/Jugador/byTeam/:id_equipo',   to: 'api/jugadores#by_team'

    # Localidad
    get    '/Localidad',                   to: 'api/localidades#index'
    post   '/Localidad',                   to: 'api/localidades#create'
    get    '/Localidad/Paginado',          to: 'api/localidades#paginado'
    get    '/Localidad/:id',               to: 'api/localidades#show'
    put    '/Localidad/:id',               to: 'api/localidades#update'
    delete '/Localidad/:id',               to: 'api/localidades#destroy'

    # Anotacion (ejemplo)
    get    '/Anotacion',                   to: 'api/anotaciones#index'
    post   '/Anotacion',                   to: 'api/anotaciones#create'
    get    '/Anotacion/:id',               to: 'api/anotaciones#show'
    put    '/Anotacion/:id',               to: 'api/anotaciones#update'
    delete '/Anotacion/:id',               to: 'api/anotaciones#destroy'
    get    '/Anotacion/jugador/:id',       to: 'api/anotaciones#by_jugador'
  end
end
