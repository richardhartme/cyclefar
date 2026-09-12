class AddEventReasonToTimeOffPeriods < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :time_off_periods, name: "time_off_periods_reason_values"
    remove_check_constraint :time_off_periods, name: "time_off_periods_return_ramp"
    add_check_constraint :time_off_periods,
      "reason IN ('holiday', 'illness', 'recovery', 'event', 'other')",
      name: "time_off_periods_reason_values"
    add_check_constraint :time_off_periods,
      "(reason IN ('illness', 'recovery') AND return_ramp_days IS NOT NULL AND return_ramp_days > 0) OR (reason IN ('holiday', 'event', 'other') AND return_ramp_days IS NULL)",
      name: "time_off_periods_return_ramp"
  end

  def down
    remove_check_constraint :time_off_periods, name: "time_off_periods_reason_values"
    remove_check_constraint :time_off_periods, name: "time_off_periods_return_ramp"
    add_check_constraint :time_off_periods,
      "reason IN ('holiday', 'illness', 'recovery', 'other')",
      name: "time_off_periods_reason_values"
    add_check_constraint :time_off_periods,
      "(reason IN ('illness', 'recovery') AND return_ramp_days IS NOT NULL AND return_ramp_days > 0) OR (reason IN ('holiday', 'other') AND return_ramp_days IS NULL)",
      name: "time_off_periods_return_ramp"
  end
end
