require "rails_helper"

RSpec.describe "Health check", type: :request do
  it "returns success to an unauthenticated container probe" do
    host! "localhost"

    get rails_health_check_path, headers: { "User-Agent" => "curl/8.0.0" }

    expect(response).to have_http_status(:ok)
    expect(response.headers["Location"]).to be_nil
    expect(response.headers["Set-Cookie"]).to be_nil
  end
end
