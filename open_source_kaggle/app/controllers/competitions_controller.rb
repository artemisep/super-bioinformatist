class CompetitionsController < ApplicationController
  before_action :authenticate_user!, except: [:index, :show]
  before_action :set_competition, only: [:show, :edit, :update, :destroy]

  def index
    @competitions = Competition.all
  end

  def show
  end

  def new
    @competition = current_user.competitions.build
  end

  def create
    @competition = current_user.competitions.build(competition_params)
    if @competition.save
      redirect_to @competition, notice: "Competition was successfully created."
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @competition.update(competition_params)
      redirect_to @competition, notice: "Competition was successfully updated."
    else
      render :edit
    end
  end

  def destroy
    @competition.destroy
    redirect_to competitions_url, notice: "Competition was successfully destroyed."
  end

  private

  def set_competition
    @competition = Competition.find(params[:id])
  end

  def competition_params
    params.require(:competition).permit(:title, :description, :start_date, :end_date)
  end
end
