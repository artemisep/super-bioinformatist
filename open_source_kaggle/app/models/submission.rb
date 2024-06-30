class Submission < ApplicationRecord
  belongs_to :competition
  belongs_to :user

  mount_uploader :file, FileUploader
end
