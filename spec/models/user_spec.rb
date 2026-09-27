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
end
