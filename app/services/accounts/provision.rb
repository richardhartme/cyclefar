require "uri/mailto"

module Accounts
  class Provision
    def initialize(email_address:)
      @email_address = email_address.to_s.strip.downcase
    end

    def call
      raise ArgumentError, "Provide a valid email address" unless URI::MailTo::EMAIL_REGEXP.match?(@email_address)

      User.transaction do
        user = User.create!(email_address: @email_address, password: SecureRandom.hex(32))
        PasswordsMailer.reset(user).deliver_now
        user
      end
    end
  end
end
