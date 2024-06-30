# config/routes.rb
Rails.application.routes.draw do
  devise_for :users
  root "competitions#index"

  resources :competitions do
    resources :submissions, only: [:create, :new, :index]
    post "evaluate", on: :member
  end
end
