# app/models/competition.rb
class Competition < ApplicationRecord
  belongs_to :user
  has_many :submissions, dependent: :destroy
  has_one_attached :evaluation_dataset  # Add this line
end
