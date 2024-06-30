# app/controllers/competitions_controller.rb
class CompetitionsController < ApplicationController
  before_action :authenticate_user!, except: [:index, :show]
  before_action :set_competition, only: [:show, :edit, :update, :destroy, :evaluate]

  def index
    @competitions = Competition.all
  end

  def show
  end

  def new
    @competition = Competition.new
  end

  def create
    @competition = Competition.new(competition_params)
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

  def evaluate
    uploaded_file = params[:evaluation_dataset]
    dataset_path = Rails.root.join("storage", "evaluation", uploaded_file.original_filename)
    File.open(dataset_path, "wb") do |file|
      file.write(uploaded_file.read)
    end

    submission = Submission.find(params[:submission_id])
    model_path = Rails.root.join(submission.model_file.path)

    results = run_model_and_evaluate(model_path, dataset_path)

    render json: { results: results }
  end

  private

  def set_competition
    @competition = Competition.find(params[:id])
  end

  def competition_params
    params.require(:competition).permit(:name, :description, :start_date, :end_date)
  end

  def run_model_and_evaluate(model_path, dataset_path)
    response = HTTParty.post("http://localhost:5000/evaluate",
                             body: { model_path: model_path.to_s, dataset_path: dataset_path.to_s }.to_json,
                             headers: { "Content-Type" => "application/json" })
    response.parsed_response
  end
end
