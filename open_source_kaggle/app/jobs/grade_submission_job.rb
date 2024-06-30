# app/jobs/grade_submission_job.rb
class GradeSubmissionJob < ApplicationJob
  queue_as :default

  def perform(submission_id)
    submission = Submission.find(submission_id)
    # Path to the submission file
    submission_file_path = Rails.root.join("storage", submission.file)

    # Run the grading script (replace this with your actual grading logic)
    grade, feedback = run_grading_script(submission_file_path)

    # Save the grade and feedback to the submission
    submission.update(score: grade, feedback: feedback)
  end

  private

  def run_grading_script(file_path)
    # Dummy implementation of the grading logic
    # Replace this with the actual script execution and grading logic
    grade = rand(0..100)
    feedback = "Feedback for the submission at #{file_path}"
    [grade, feedback]
  end
end
