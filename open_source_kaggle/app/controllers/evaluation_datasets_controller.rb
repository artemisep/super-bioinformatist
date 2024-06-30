class EvaluationDatasetsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_competition

  def index
    @evaluation_datasets = @competition.evaluation_datasets
  end

  def new
    @evaluation_dataset = @competition.evaluation_datasets.build
  end

  def create
    @evaluation_dataset = @competition.evaluation_datasets.build(evaluation_dataset_params)
    if @evaluation_dataset.save
      redirect_to competition_evaluation_datasets_path(@competition), notice: "Evaluation dataset was successfully uploaded."
    else
      render :new
    end
  end

  private

  def set_competition
    @competition = Competition.find(params[:competition_id])
  end

  def evaluation_dataset_params
    params.require(:evaluation_dataset).permit(:file)
  end
end
