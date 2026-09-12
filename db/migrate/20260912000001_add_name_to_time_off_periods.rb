class AddNameToTimeOffPeriods < ActiveRecord::Migration[8.1]
  def change
    add_column :time_off_periods, :name, :string
  end
end
