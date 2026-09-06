require "json"
require "net/http"
require "uri"

module IntervalsIcu
  class Client
    BASE_URL = "https://intervals.icu/api/v1".freeze
    TIMEOUT_SECONDS = 5

    class Error < StandardError; end
    class AuthenticationError < Error; end
    class RequestError < Error; end
    class TransientError < StandardError; end

    def initialize(api_key:, connection_factory: nil)
      @api_key = api_key
      @connection_factory = connection_factory || method(:default_connection)
    end

    def upsert_events(events)
      request(:post, "/athlete/0/events/bulk?upsert=true", events)
    end

    def delete_events(external_ids)
      return [] if external_ids.empty?

      request(:put, "/athlete/0/events/bulk-delete", external_ids.map { |external_id| { external_id: external_id } })
    end

    private

    def request(method, path, body)
      attempts = 0
      begin
        attempts += 1
        uri = URI("#{BASE_URL}#{path}")
        request = request_class(method).new(uri)
        request.basic_auth("API_KEY", @api_key)
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(body)
        response = @connection_factory.call(uri).request(request)
        return parse_response(response) if response.code.to_i.between?(200, 299)

        raise AuthenticationError, "Intervals.icu rejected the API key" if [ 401, 403 ].include?(response.code.to_i)
        raise TransientError if response.code.to_i >= 500

        raise RequestError, "Intervals.icu could not accept the sync request"
      rescue TransientError, IOError, SocketError, Timeout::Error, Net::OpenTimeout, Net::ReadTimeout
        retry if attempts < 2

        raise RequestError, "Intervals.icu could not complete the sync request"
      end
    end

    def parse_response(response)
      JSON.parse(response.body)
    rescue JSON::ParserError
      raise RequestError, "Intervals.icu returned an invalid response"
    end

    def request_class(method)
      method == :post ? Net::HTTP::Post : Net::HTTP::Put
    end

    def default_connection(uri)
      Net::HTTP.new(uri.host, uri.port).tap do |connection|
        connection.use_ssl = true
        connection.open_timeout = TIMEOUT_SECONDS
        connection.read_timeout = TIMEOUT_SECONDS
      end
    end
  end
end
