class SubmissionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_competition

  def index
    @submissions = @competition.submissions
  end

  def new
    @submission = @competition.submissions.build
  end

  def create
    @submission = @competition.submissions.build(submission_params)
    @submission.user = current_user
    if @submission.save
      redirect_to competition_submissions_path(@competition), notice: "Submission was successfully created."
    else
      render :new
    end
  end

  private

  def set_competition
    @competition = Competition.find(params[:competition_id])
  end

  def submission_params
    params.require(:submission).permit(:file, :score)
  end
end
