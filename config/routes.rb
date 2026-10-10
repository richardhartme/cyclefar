Rails.application.routes.draw do
  resource :session
  resource :registration, only: %i[ new create ]
  resources :passwords, param: :token
  root "home#index"
  resource :settings, only: [ :show, :update ]
  resources :ftp_readings, only: [ :edit, :update, :destroy ]
  resource :training_plan, only: [ :new, :create, :destroy ] do
    get :preview
    post :preview, action: :prepare_preview
  end
  resources :planned_workouts, only: [ :new, :create, :show, :destroy ] do
    member do
      post :shuffle
      post :change
      post :move
      post :copy
      post :complete
      post :miss
    end
  end
  resources :adaptation_proposals, only: [] do
    member do
      post :accept
      delete :reject
    end
  end
  resource :availability_change, only: [ :new, :create ]
  resources :time_off_periods, only: [ :new, :create, :destroy ]
  resource :intervals_icu_sync, only: :create
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
