require "webmock/rspec"

# Specs never reach a real external API. Local connections stay open for the
# browser driver and Capybara's app server.
WebMock.disable_net_connect!(allow_localhost: true)
