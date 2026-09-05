require "rails_helper"

RSpec.describe "Home", type: :request do
  it "BRD-001 / PLN-001 shows CycleFar navigation and a working no-plan action" do
    get root_path
    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    expect(html.at_css("title").text).to eq("CycleFar")
    expect(html.css("nav a").map(&:text)).to eq([ "CycleFar", "Calendar", "Settings" ])
    action = html.css("a").find { |link| link.text == "Create training plan" }
    expect(action["href"]).to eq(new_training_plan_path)
    get action["href"]
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Plan creation is coming soon")
    expect(Nokogiri::HTML(response.body).css("form")).to be_empty
  end

  it "uses Monday-first calendar dates" do
    expect(Date.new(2026, 9, 13).beginning_of_week).to eq(Date.new(2026, 9, 7))
    expect(CycleFar::Application.module_parent_name).to eq("CycleFar")
  end
end
