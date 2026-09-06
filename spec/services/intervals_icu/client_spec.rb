require "rails_helper"

RSpec.describe IntervalsIcu::Client do
  Response = Struct.new(:code, :body)

  class RecordingConnection
    attr_reader :requests

    def initialize(responses)
      @responses = responses
      @requests = []
    end

    def request(request)
      @requests << request
      @responses.shift
    end
  end

  it "ICU-001 sends an authenticated bulk upsert to the documented API endpoint" do
    connection = RecordingConnection.new([ Response.new("200", '[{"id":42,"external_id":"cyclefar-workout-1"}]') ])
    client = described_class.new(api_key: "test-api-key", connection_factory: ->(_uri) { connection })

    response = client.upsert_events([ { external_id: "cyclefar-workout-1", name: "Endurance" } ])

    expect(response).to eq([ { "id" => 42, "external_id" => "cyclefar-workout-1" } ])
    request = connection.requests.sole
    expect(request.path).to eq("/api/v1/athlete/0/events/bulk?upsert=true")
    expect(request["Authorization"]).to eq("Basic QVBJX0tFWTp0ZXN0LWFwaS1rZXk=")
    expect(JSON.parse(request.body)).to eq([ { "external_id" => "cyclefar-workout-1", "name" => "Endurance" } ])
  end

  it "uses the bulk-delete endpoint only for supplied owned external IDs" do
    connection = RecordingConnection.new([ Response.new("200", "1") ])
    client = described_class.new(api_key: "test-api-key", connection_factory: ->(_uri) { connection })

    client.delete_events([ "cyclefar-workout-1" ])

    request = connection.requests.sole
    expect(request.method).to eq("PUT")
    expect(request.path).to eq("/api/v1/athlete/0/events/bulk-delete")
    expect(JSON.parse(request.body)).to eq([ { "external_id" => "cyclefar-workout-1" } ])
  end

  it "raises a safe authentication error for rejected API keys" do
    connection = RecordingConnection.new([ Response.new("401", '{"message":"not authorized"}') ])
    client = described_class.new(api_key: "test-api-key", connection_factory: ->(_uri) { connection })

    expect { client.upsert_events([]) }.to raise_error(IntervalsIcu::Client::AuthenticationError, "Intervals.icu rejected the API key")
  end

  it "retries a transient server failure once and returns a safe error when it persists" do
    connection = RecordingConnection.new([ Response.new("500", "failure"), Response.new("503", "failure") ])
    client = described_class.new(api_key: "test-api-key", connection_factory: ->(_uri) { connection })

    expect { client.upsert_events([]) }.to raise_error(IntervalsIcu::Client::RequestError, "Intervals.icu could not complete the sync request")
    expect(connection.requests.size).to eq(2)
  end
end
