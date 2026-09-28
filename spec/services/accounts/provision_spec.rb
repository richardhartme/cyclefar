require "rails_helper"

RSpec.describe Accounts::Provision do
  it "USR-001 refuses an invalid or existing address without sending mail" do
    create(:user, email_address: "existing@example.com")
    ActionMailer::Base.deliveries.clear

    expect { described_class.new(email_address: "invalid").call }.to raise_error(ArgumentError, /email address/)
    expect { described_class.new(email_address: "existing@example.com").call }.to raise_error(ActiveRecord::RecordInvalid)
    expect(ActionMailer::Base.deliveries).to be_empty
  ensure
    ActionMailer::Base.deliveries.clear
  end

  it "does not retain an unusable account if mail delivery fails" do
    delivery = instance_double(ActionMailer::MessageDelivery)
    allow(delivery).to receive(:deliver_now).and_raise(StandardError, "SMTP unavailable")
    allow(PasswordsMailer).to receive(:reset).and_return(delivery)

    expect { described_class.new(email_address: "new@example.com").call }.to raise_error(StandardError, "SMTP unavailable")
    expect(User.where(email_address: "new@example.com")).not_to exist
  end
end
