Rails.application.routes.draw do
  devise_for :users
  root "competitions#index"

  resources :competitions do
    resources :submissions, only: [:create, :new, :index]
    resources :evaluation_datasets, only: [:create, :new, :index]
  end
end
