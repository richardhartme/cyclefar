if Rails.env.development?
  email = ENV.fetch("CYCLEFAR_SEED_USER_EMAIL")
  user = User.find_by!(email_address: email.strip.downcase)
  if user.training_plans.active.exists?
    puts "A training plan already exists; development sample data was not added."
  else
    Settings::Update.new(profile: user.rider_profile || user.build_rider_profile, attributes: { ftp_watts: 260 }).call

    configuration = Planning::PlanConfiguration.new(
      goal: "increase_ftp",
      discipline: "road",
      starts_on: Date.current.next_occurring(:monday),
      duration_mode: "custom",
      custom_duration_weeks: 12,
      ftp_watts: 260,
      include_base: true,
      progression_mode: "hard_recovery_cycle",
      hard_weeks_before_recovery: 3,
      availability: {
        "2" => { enabled: "1", weekday: 2, duration_minutes: 60, intent: "intervals" },
        "4" => { enabled: "1", weekday: 4, duration_minutes: 90, intent: "endurance" },
        "6" => { enabled: "1", weekday: 6, duration_minutes: 60, intent: "intervals" },
        "7" => { enabled: "1", weekday: 7, duration_minutes: 120, intent: "endurance" }
      }
    )

    raise "Development sample plan is invalid: #{configuration.errors.full_messages.to_sentence}" unless configuration.valid?

    plan = Planning::PlanCreator.new(configuration, user: user).create!
    puts "Created a 12-week CycleFar development sample plan (FTP #{plan.initial_ftp_watts} W)."
  end
end
