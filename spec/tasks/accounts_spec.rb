require "rails_helper"
require "rake"

Rails.application.load_tasks unless Rake::Task.task_defined?("accounts:provision")

RSpec.describe "accounts:provision" do
  let(:task) { Rake::Task["accounts:provision"] }

  around do |example|
    original_flag = ENV["CYCLEFAR_RIDER_PROVISIONING_ENABLED"]
    original_email = ENV["EMAIL_ADDRESS"]
    task.reenable
    ActionMailer::Base.deliveries.clear
    example.run
  ensure
    ENV["CYCLEFAR_RIDER_PROVISIONING_ENABLED"] = original_flag
    ENV["EMAIL_ADDRESS"] = original_email
    ActionMailer::Base.deliveries.clear
    task.reenable
  end

  it "keeps provisioning disabled until the release gate is explicitly enabled" do
    ENV.delete("CYCLEFAR_RIDER_PROVISIONING_ENABLED")
    ENV["EMAIL_ADDRESS"] = "new@example.com"

    expect { expect { task.invoke }.to raise_error(SystemExit) }.to output(/disabled until the two-user release gate/).to_stderr
    expect(User.where(email_address: "new@example.com")).not_to exist
  end

  it "creates one account and delivers its setup mail when enabled" do
    ENV["CYCLEFAR_RIDER_PROVISIONING_ENABLED"] = "true"
    ENV["EMAIL_ADDRESS"] = "new@example.com"

    expect { expect { task.invoke }.to change(User, :count).by(1) }.to output(/Provisioned new@example.com/).to_stdout
    expect(ActionMailer::Base.deliveries.sole.to).to eq([ "new@example.com" ])
  end
end
