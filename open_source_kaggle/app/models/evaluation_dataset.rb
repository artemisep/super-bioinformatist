class EvaluationDataset < ApplicationRecord
  belongs_to :competition
  mount_uploader :file, FileUploader
end
