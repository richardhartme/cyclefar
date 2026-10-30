# Selenium Manager otherwise reports usage stats over the network.
ENV["SE_AVOID_STATS"] ||= "true"
Capybara.enable_aria_label = true

RSpec.configure do |config|
  config.before(:each, type: :system) do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1000 ] do |options|
      # Chrome's password-manager and breach-warning bubbles take input focus
      # from the page after sign-in, silently dropping later keystrokes and clicks.
      options.add_preference("credentials_enable_service", false)
      options.add_preference("profile.password_manager_enabled", false)
      options.add_preference("profile.password_manager_leak_detection", false)
      options.add_argument("--disable-features=PasswordLeakDetection,PasswordManagerOnboarding")
    end
  end
end
