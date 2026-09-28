require "rails_helper"

RSpec.describe "Authentication", type: :request do
  it "redirects protected pages to sign in and resumes the requested page" do
    user = create(:user)

    get settings_path
    expect(response).to redirect_to(new_session_path)

    post session_path, params: { email_address: user.email_address, password: "password" }
    expect(response).to redirect_to(settings_path)
    expect(user.sessions.count).to eq(1)

    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Current FTP (watts)")
  end

  it "rejects invalid credentials without creating a session" do
    user = create(:user)

    post session_path, params: { email_address: user.email_address, password: "wrong-password" }

    expect(response).to redirect_to(new_session_path)
    expect(user.sessions.count).to eq(0)
  end

  it "destroys the login session on sign out" do
    user = create(:user)
    sign_in_as(user)

    delete session_path

    expect(response).to redirect_to(new_session_path)
    expect(user.sessions.count).to eq(0)
    get root_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Sign In", "Register")
  end

  it "invalidates existing sessions when the password is reset" do
    user = create(:user)
    sign_in_as(user)

    put password_path(user.password_reset_token), params: { password: "replacement-password", password_confirmation: "replacement-password" }

    expect(response).to redirect_to(new_session_path)
    expect(user.reload.authenticate("replacement-password")).to eq(user)
    expect(user.sessions.count).to eq(0)
    get settings_path
    expect(response).to redirect_to(new_session_path)
  end
end
