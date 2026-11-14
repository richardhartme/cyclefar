# GAR-006: rowing becomes its own sport. Garmin rows already imported as
# `other` are remapped from their stored type key.
class AddRowingToActivitySports < ActiveRecord::Migration[8.1]
  OLD_SPORTS = %w[cycling running walking strength yoga swimming other].freeze
  NEW_SPORTS = %w[cycling running walking strength yoga swimming rowing other].freeze
  ROWING_KEYS = %w[indoor_rowing rowing].freeze

  def up
    replace_constraint(NEW_SPORTS)
    execute <<~SQL
      UPDATE activities SET sport = 'rowing'
      WHERE source = 'garmin' AND sport = 'other' AND external_type IN (#{ROWING_KEYS.map { |key| connection.quote(key) }.join(', ')})
    SQL
  end

  def down
    execute "UPDATE activities SET sport = 'other' WHERE sport = 'rowing'"
    replace_constraint(OLD_SPORTS)
  end

  private

  def replace_constraint(sports)
    remove_check_constraint :activities, name: "activities_sport"
    add_check_constraint :activities, "sport IN (#{sports.map { |sport| connection.quote(sport) }.join(', ')})", name: "activities_sport"
  end
end
