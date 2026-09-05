# Local keys are generated once by bin/setup; never commit or rotate them casually.
# Explicit environment configuration also supports separate databases/installations.
encryption = Rails.application.config.active_record.encryption
%w[primary_key deterministic_key key_derivation_salt].each do |name|
  value = ENV["ACTIVE_RECORD_ENCRYPTION_#{name.upcase}"]
  if Rails.env.test?
    value ||= "cycle-far-test-only-#{name}-never-use-outside-tests"
  elsif Rails.env.development?
    key_file = Rails.root.join("config", "active_record_encryption.#{name}.key")
    value ||= key_file.read.strip if key_file.exist?
  end
  encryption.public_send("#{name}=", value) if value.present?
end
