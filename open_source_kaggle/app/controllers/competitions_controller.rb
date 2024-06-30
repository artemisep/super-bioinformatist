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
    require "tensorflow"

    model = TensorFlow::Keras::Models.load_model(model_path.to_s)
    dataset = CSV.read(dataset_path, headers: true).map { |row| row.to_hash }

    # Prepare your dataset for evaluation
    # ...

    predictions = model.predict(dataset)

    ground_truth = dataset.map { |row| row["label"] }
    accuracy = compute_accuracy(predictions, ground_truth)

    { accuracy: accuracy }
  end

  def compute_accuracy(predictions, ground_truth)
    correct = predictions.zip(ground_truth).count { |pred, truth| pred == truth }
    correct.to_f / ground_truth.size
  end
end
