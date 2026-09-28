require "rails_helper"

RSpec.describe "Registration", type: :request do
  it "shows Sign In and Register from the public homepage" do
    get root_path

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    expect(html.at_css("main h1").text).to eq("Plan smart. Ride far.")
    expect(html.at_css("main a[href='#{new_session_path}']").text).to eq("Sign In")
    expect(html.at_css("main a[href='#{new_registration_path}']").text).to eq("Register")

    get new_session_path
    expect(Nokogiri::HTML(response.body).at_css("main a[href='#{new_registration_path}']").text).to eq("Register")
  end

  it "creates an account, signs in, and opens the private calendar" do
    get new_registration_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Create account")

    expect do
      post registration_path, params: { user: { email_address: " New@Example.com ", password: "secure-password", password_confirmation: "secure-password" } }
    end.to change(User, :count).by(1)

    user = User.find_by!(email_address: "new@example.com")
    expect(user.sessions.count).to eq(1)
    expect(response).to redirect_to(root_path)

    follow_redirect!
    expect(response.body).to include("Training calendar", "Create training plan", "new@example.com")
    expect(Nokogiri::HTML(response.body).at_css("main h1").text).to eq("Training calendar")
    get settings_path
    expect(response).to have_http_status(:ok)
  end

  it "rejects duplicate emails and mismatched or missing password confirmations" do
    create(:user, email_address: "existing@example.com")

    [
      { email_address: "EXISTING@example.com", password: "secure-password", password_confirmation: "secure-password" },
      { email_address: "not-an-email", password: "secure-password", password_confirmation: "secure-password" },
      { email_address: "new@example.com", password: "secure-password", password_confirmation: "different" },
      { email_address: "new@example.com", password: "secure-password" }
    ].each do |attributes|
      expect { post registration_path, params: { user: attributes } }.not_to change(User, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('role="alert"')
    end

    get settings_path
    expect(response).to redirect_to(new_session_path)
  end

  it "keeps a signed-in rider on their calendar when they visit registration" do
    user = create(:user)
    sign_in_as(user)

    get new_registration_path
    expect(response).to redirect_to(root_path)
    post registration_path, params: { user: { email_address: "another@example.com", password: "secure-password", password_confirmation: "secure-password" } }
    expect(response).to redirect_to(root_path)
    expect(User.find_by(email_address: "another@example.com")).to be_nil
  end
end
