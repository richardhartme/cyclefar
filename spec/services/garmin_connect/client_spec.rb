require "rails_helper"

RSpec.describe GarminConnect::Client do
  let(:api_key) { "personal-api-key-secret" }
  let(:token) { "eyJhbGciOiJSUzI1NiJ9.eyJleHAiOjE3OTk5OTk5OTl9.signature-secret" }
  let(:client) { described_class.new(api_key: api_key) }
  let(:token_url) { "https://personal.connectapi.garmin.com/personalapitoken-service/personal-api/personal-api-key/token" }
  let(:list_url) { "https://personal.connectapi.garmin.com/activitylist-service/activities/search/activities" }
  let(:payloads) { JSON.parse(file_fixture("garmin_connect/activities.json").read) }

  def stub_token
    stub_request(:post, token_url)
      .with(headers: { "Authorization" => "ApiKey #{api_key}" })
      .to_return(status: 200, body: "#{token}\n", headers: { "Content-Type" => "text/plain" })
  end

  def stub_page(start, body, limit: described_class::PAGE_SIZE)
    stub_request(:get, list_url)
      .with(
        query: { startDate: "2026-11-01", endDate: "2026-11-14", start: start.to_s, limit: limit.to_s },
        headers: { "Authorization" => "Bearer #{token}" })
      .to_return(status: 200, body: JSON.generate(body), headers: { "Content-Type" => "application/json" })
  end

  def activities
    client.activities(from: Date.new(2026, 11, 1), to: Date.new(2026, 11, 14))
  end

  describe "#activities" do
    it "exchanges the key for a plain-text token and lists the window's activities with it" do
      token_request = stub_token
      stub_page(0, payloads)

      summaries = activities

      expect(token_request).to have_been_requested.once
      expect(summaries).to all(be_a(GarminConnect::ActivitySummary))
      expect(summaries.map(&:garmin_activity_id)).to eq([ 25_012_345_678, 25_012_345_701, 25_012_345_722 ])
    end

    it "follows the paging until a short page, reusing one token" do
      stub_const("#{described_class}::PAGE_SIZE", 2)
      token_request = stub_token
      stub_page(0, payloads.first(2), limit: 2)
      stub_page(2, payloads.last(1), limit: 2)

      expect(activities.map(&:garmin_activity_id)).to eq([ 25_012_345_678, 25_012_345_701, 25_012_345_722 ])
      expect(token_request).to have_been_requested.once
    end

    it "stops at an empty page when the last full page ends the listing exactly" do
      stub_const("#{described_class}::PAGE_SIZE", 3)
      stub_token
      stub_page(0, payloads, limit: 3)
      last_page = stub_page(3, [], limit: 3)

      expect(activities.size).to eq(3)
      expect(last_page).to have_been_requested.once
    end
  end

  describe "#activity_file" do
    let(:fit_bytes) { file_fixture("fit/indoor_ride.fit").binread }
    let(:file_url) { "https://personal.connectapi.garmin.com/download-service/files/activity/25012345678" }

    def zip(entries)
      Zip::OutputStream.write_buffer do |zip|
        entries.each do |name, bytes|
          zip.put_next_entry(name)
          zip.write(bytes)
        end
      end.string
    end

    def stub_file(body)
      stub_request(:get, file_url)
        .with(headers: { "Authorization" => "Bearer #{token}" })
        .to_return(status: 200, body: body, headers: { "Content-Type" => "application/x-zip-compressed" })
    end

    it "downloads the original file and unzips it to FIT bytes Fit::Reader accepts" do
      stub_token
      stub_file(zip("25012345678_ACTIVITY.fit" => fit_bytes))

      bytes = client.activity_file(25_012_345_678)

      expect(bytes).to eq(fit_bytes)
      expect(bytes.encoding).to eq(Encoding::BINARY)
      expect(Fit::Reader.new(bytes).samples).not_to be_empty
    end

    it "rejects a download that is not a zip holding exactly one .fit file" do
      stub_token
      archives = [
        "not a zip at all",
        zip({}),
        zip("activity.csv" => "time,power\n"),
        zip("one.fit" => fit_bytes, "two.fit" => fit_bytes)
      ]

      archives.each do |archive|
        stub_file(archive)
        expect { client.activity_file(25_012_345_678) }
          .to raise_error(GarminConnect::Client::InvalidFileError, "Garmin sent an activity file CycleFar can't read.")
      end
    end

    it "rejects an unzipped file over the upload size limit" do
      stub_const("Activity::MAXIMUM_FILE_SIZE", 1_000)
      stub_token
      stub_file(zip("activity.fit" => fit_bytes))

      expect { client.activity_file(25_012_345_678) }.to raise_error(GarminConnect::Client::InvalidFileError)
    end
  end

  describe "errors" do
    let(:rejected_key) { "Your Garmin key was rejected or has expired. Update it in Settings." }

    it "raises an authentication error when the token exchange rejects the key" do
      stub_request(:post, token_url).to_return(status: 401, body: "")

      expect { activities }.to raise_error(GarminConnect::Client::AuthenticationError, rejected_key)
    end

    it "raises an authentication error when a later call is forbidden" do
      stub_token
      stub_request(:get, /#{list_url}/o).to_return(status: 403, body: '{"message":"Forbidden"}')

      expect { activities }.to raise_error(GarminConnect::Client::AuthenticationError, rejected_key)
    end

    describe "rate limiting" do
      def rate_limited(headers = {})
        stub_token
        stub_request(:get, /#{list_url}/o).to_return(status: 429, body: "Too Many Requests", headers: headers)
        activities
      rescue GarminConnect::Client::RateLimitedError => error
        error
      end

      it "reports Retry-After seconds" do
        error = rate_limited("Retry-After" => "120")

        expect(error.retry_after).to eq(120)
        expect(error.message).to eq("Garmin is rate limiting requests. Try again in 2 minutes.")
      end

      it "reports a Retry-After date as seconds from now" do
        travel_to Time.utc(2026, 11, 14, 9, 0, 0) do
          error = rate_limited("Retry-After" => "Sat, 14 Nov 2026 09:00:45 GMT")

          expect(error.retry_after).to eq(45)
          expect(error.message).to eq("Garmin is rate limiting requests. Try again in 45 seconds.")
        end
      end

      it "reports rate limiting without a usable Retry-After" do
        [ {}, { "Retry-After" => "soon" } ].each do |headers|
          error = rate_limited(headers)

          expect(error.retry_after).to be_nil
          expect(error.message).to eq("Garmin is rate limiting requests.")
        end
      end
    end

    describe "remote failures" do
      let(:unavailable) { "Garmin Connect is unavailable. Try again later." }

      it "raises a remote error for server errors and unexpected statuses, without retrying" do
        [ 500, 503, 404, 302 ].each do |status|
          WebMock.reset!
          stub_token
          listing = stub_request(:get, /#{list_url}/o).to_return(status: status, body: "<html>oops</html>")

          expect { activities }.to raise_error(GarminConnect::Client::RemoteError, unavailable)
          expect(listing).to have_been_requested.once
        end
      end

      it "raises a remote error for timeouts and connection failures, without retrying" do
        [ Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, Errno::ECONNRESET, SocketError, OpenSSL::SSL::SSLError, EOFError ].each do |failure|
          WebMock.reset!
          token_request = stub_request(:post, token_url).to_raise(failure)

          expect { activities }.to raise_error(GarminConnect::Client::RemoteError, unavailable)
          expect(token_request).to have_been_requested.once
        end
      end

      it "raises a remote error for a blank token or a listing CycleFar can't read" do
        stub_request(:post, token_url).to_return(status: 200, body: " \n")
        expect { activities }.to raise_error(GarminConnect::Client::RemoteError, unavailable)

        [ "not json", '{"activities":[]}', JSON.generate([ payloads.first.except("startTimeGMT") ]) ].each do |body|
          WebMock.reset!
          stub_token
          stub_request(:get, /#{list_url}/o).to_return(status: 200, body: body)

          expect { activities }.to raise_error(GarminConnect::Client::RemoteError, unavailable)
        end
      end

      it "raises a remote error rather than returning a listing Garmin never finishes" do
        stub_const("#{described_class}::PAGE_SIZE", 1)
        stub_const("#{described_class}::MAXIMUM_PAGES", 3)
        stub_token
        listing = stub_request(:get, /#{list_url}/o).to_return(status: 200, body: JSON.generate(payloads.first(1)))

        expect { activities }.to raise_error(GarminConnect::Client::RemoteError, unavailable)
        expect(listing).to have_been_requested.times(3)
      end
    end

    it "never exposes the key or token in errors, the client or the log" do
      failures = {
        "rejected key" => -> { stub_request(:post, token_url).to_return(status: 401, body: "bad key #{api_key}") },
        "network failure naming the key" => -> { stub_request(:post, token_url).to_raise(SocketError.new("failed for #{api_key}")) },
        "rate limited" => -> { stub_token && stub_request(:get, /#{list_url}/o).to_return(status: 429, body: token) },
        "server error echoing the token" => -> { stub_token && stub_request(:get, /#{list_url}/o).to_return(status: 500, body: token) },
        "unreadable body echoing the token" => -> { stub_token && stub_request(:get, /#{list_url}/o).to_return(status: 200, body: "oops #{token}") },
        "unreadable file" => -> { stub_token && stub_request(:get, /download-service/).to_return(status: 200, body: "PK #{token}") }
      }
      log = StringIO.new
      allow(Rails).to receive(:logger).and_return(ActiveSupport::Logger.new(log))

      failures.each do |name, stub|
        WebMock.reset!
        stub.call
        fresh_client = described_class.new(api_key: api_key)
        error = begin
          name == "unreadable file" ? fresh_client.activity_file(1) : fresh_client.activities(from: Date.new(2026, 11, 1), to: Date.new(2026, 11, 14))
        rescue GarminConnect::Client::Error => raised
          raised
        end

        exposed = [ error.message, error.full_message, error.inspect, fresh_client.inspect, log.string ].join("\n")
        expect(error.cause).to be_nil, name
        expect(error).to be_a(GarminConnect::Client::Error), name
        expect(exposed).not_to include(api_key), name
        expect(exposed).not_to include(token), name
      end
    end
  end
end
