class CreateEvaluationDatasets < ActiveRecord::Migration[7.1]
  def change
    create_table :evaluation_datasets do |t|
      t.references :competition, null: false, foreign_key: true
      t.string :file

      t.timestamps
    end
  end
end
