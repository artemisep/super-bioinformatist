# app/models/submission.rb
class Submission < ApplicationRecord
  belongs_to :competition
  belongs_to :user

  mount_uploader :model_file, ModelUploader  # Add this line for model file upload

  attribute :feedback, :string
end
