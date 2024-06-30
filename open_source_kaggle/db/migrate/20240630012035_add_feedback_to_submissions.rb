class AddFeedbackToSubmissions < ActiveRecord::Migration[7.1]
  def change
    add_column :submissions, :feedback, :string
  end
end
