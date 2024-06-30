class Competition < ApplicationRecord
  belongs_to :user
  has_many :submissions, dependent: :destroy
  has_many :evaluation_datasets, dependent: :destroy
end
