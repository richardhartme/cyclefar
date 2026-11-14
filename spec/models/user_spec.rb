require "rails_helper"

RSpec.describe User, type: :model do
  it "normalizes email addresses and authenticates with a password digest" do
    user = create(:user, email_address: " Rider@Example.com ")

    expect(user.reload.email_address).to eq("rider@example.com")
    expect(user.password_digest).not_to eq("password")
    expect(user.authenticate("password")).to eq(user)
    expect(user.authenticate("wrong-password")).to be_falsey
  end

  it "removes database sessions when the user is destroyed" do
    user = create(:user)
    user.sessions.create!

    expect { user.destroy! }.to change(Session, :count).by(-1)
  end

  describe "GAR-001 #garmin_rider?" do
    let(:user) { create(:user, email_address: "rider@example.com") }

    it "is true only for the user GARMIN_RIDER_EMAIL names, ignoring case and spaces" do
      with_garmin_rider_email(" Rider@Example.COM ") do
        expect(user).to be_garmin_rider
        expect(create(:user)).not_to be_garmin_rider
      end
    end

    it "is false for everyone when GARMIN_RIDER_EMAIL is unset or blank" do
      [ nil, "", "  " ].each do |email|
        with_garmin_rider_email(email) { expect(user).not_to be_garmin_rider }
      end
    end
  end
end
