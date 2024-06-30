class CreateSubmissions < ActiveRecord::Migration[7.1]
  def change
    create_table :submissions do |t|
      t.references :competition, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :file
      t.float :score

      t.timestamps
    end
  end
end
