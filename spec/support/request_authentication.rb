module RequestAuthentication
  def sign_in_as(user, password: "password")
    post session_path, params: { email_address: user.email_address, password: password }
    expect(response).to redirect_to(root_path)
  end
end

RSpec.configure do |config|
  config.include RequestAuthentication, type: :request
end
