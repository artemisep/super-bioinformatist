# app/models/submission.rb
class Submission < ApplicationRecord
  belongs_to :competition
  belongs_to :user

  mount_uploader :file, FileUploader

  # Add a feedback column to store grading feedback
  attribute :feedback, :string
end
