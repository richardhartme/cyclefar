namespace :accounts do
  desc "Provision one rider account and email a password setup link (EMAIL_ADDRESS=...)"
  task provision: :environment do
    abort "Rider provisioning is disabled until CYCLEFAR_RIDER_PROVISIONING_ENABLED is set to true" unless ENV["CYCLEFAR_RIDER_PROVISIONING_ENABLED"] == "true"

    email_address = ENV.fetch("EMAIL_ADDRESS") { abort "Set EMAIL_ADDRESS to the rider's email address" }
    user = Accounts::Provision.new(email_address: email_address).call
    puts "Provisioned #{user.email_address}; password setup email sent."
  rescue ArgumentError, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
    abort "Could not provision rider: #{error.message}"
  end
end
