require "json"
require "net/http"
require "uri"

module GarminConnect
  # HTTP client for the Garmin Connect Personal API (docs/GARMIN_CONNECT.md).
  # Build one per import: it exchanges the key for a token on first use and
  # holds that token in memory only. It never retries; the rider re-runs.
  class Client
    BASE_URL = "https://personal.connectapi.garmin.com".freeze
    TOKEN_PATH = "/personalapitoken-service/personal-api/personal-api-key/token".freeze
    ACTIVITIES_PATH = "/activitylist-service/activities/search/activities".freeze
    FILE_PATH = "/download-service/files/activity/%d".freeze
    OPEN_TIMEOUT_SECONDS = 5
    READ_TIMEOUT_SECONDS = 10
    PAGE_SIZE = 100
    # A listing that hasn't ended by now is treated as broken, not partial.
    MAXIMUM_PAGES = 100
    NETWORK_ERRORS = [ IOError, SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError ].freeze

    # Every error carries a fixed, rider-readable message: never Garmin's
    # response body, the key or the token. Errors raised while rescuing pass
    # cause: nil, so the lower-level error can't carry them into a log either.
    class Error < StandardError
      MESSAGE = "Garmin Connect import failed.".freeze

      def initialize(message = self.class::MESSAGE)
        super
      end
    end

    class AuthenticationError < Error
      MESSAGE = "Your Garmin key was rejected or has expired. Update it in Settings.".freeze
    end

    class RateLimitedError < Error
      MESSAGE = "Garmin is rate limiting requests.".freeze

      # Seconds Garmin asked us to wait, or nil when it didn't say.
      attr_reader :retry_after

      def initialize(retry_after: nil)
        @retry_after = retry_after
        super(retry_after ? "#{MESSAGE} Try again in #{wait_in_words}." : MESSAGE)
      end

      private

      def wait_in_words
        return "#{retry_after} #{"second".pluralize(retry_after)}" if retry_after < 60

        minutes = (retry_after / 60.0).ceil
        "#{minutes} #{"minute".pluralize(minutes)}"
      end
    end

    # Timeouts, connection failures, 5xx and anything else Garmin sends that
    # CycleFar can't use.
    class RemoteError < Error
      MESSAGE = "Garmin Connect is unavailable. Try again later.".freeze
    end

    class InvalidFileError < Error
      MESSAGE = "Garmin sent an activity file CycleFar can't read.".freeze
    end

    def initialize(api_key:)
      @api_key = api_key
    end

    # Every activity whose local start date is in from..to, across all pages.
    # Raises rather than returning a partial listing.
    def activities(from:, to:)
      summaries = []
      MAXIMUM_PAGES.times do |page_number|
        query = { startDate: from.iso8601, endDate: to.iso8601, start: page_number * PAGE_SIZE, limit: PAGE_SIZE }
        page = parse_listing(get("#{ACTIVITIES_PATH}?#{URI.encode_www_form(query)}").body)
        summaries.concat(page)
        return summaries if page.size < PAGE_SIZE
      end
      raise RemoteError
    end

    # The activity's original .fit file, unzipped, as binary bytes. Garmin
    # sends a zip holding exactly one .fit; anything else is an invalid file.
    def activity_file(garmin_activity_id)
      archive = get(format(FILE_PATH, garmin_activity_id)).body
      begin
        entries = Zip::File.open_buffer(StringIO.new(archive.to_s)).entries.select(&:file?)
      rescue Zip::Error
        raise InvalidFileError, cause: nil
      end
      raise InvalidFileError unless entries.one? && File.extname(entries.first.name).casecmp?(".fit")

      unzip(entries.first)
    end

    def inspect
      "#<#{self.class.name}>"
    end

    private

    def token
      @token ||= begin
        request = Net::HTTP::Post.new(uri(TOKEN_PATH))
        request["Authorization"] = "ApiKey #{@api_key}"
        token = perform(request).body.to_s.strip
        raise RemoteError if token.empty?

        token
      end
    end

    def get(path)
      request = Net::HTTP::Get.new(uri(path))
      request["Authorization"] = "Bearer #{token}"
      perform(request)
    end

    def perform(request)
      response = begin
        Net::HTTP.start(
          request.uri.host,
          request.uri.port,
          use_ssl: true,
          open_timeout: OPEN_TIMEOUT_SECONDS,
          read_timeout: READ_TIMEOUT_SECONDS) { |http| http.request(request) }
      rescue *NETWORK_ERRORS
        raise RemoteError, cause: nil
      end

      case response
      when Net::HTTPSuccess then response
      when Net::HTTPUnauthorized, Net::HTTPForbidden then raise AuthenticationError
      when Net::HTTPTooManyRequests then raise RateLimitedError.new(retry_after: retry_after(response["Retry-After"]))
      else raise RemoteError
      end
    end

    def parse_listing(body)
      payloads = JSON.parse(body.to_s)
      raise RemoteError unless payloads.is_a?(Array)

      payloads.map { |payload| ActivitySummary.from_payload(payload) }
    rescue JSON::ParserError, ActivitySummary::InvalidPayload
      raise RemoteError, cause: nil
    end

    # Retry-After is either delay-seconds or an HTTP date.
    def retry_after(value)
      return if value.blank?
      return value.to_i if value.match?(/\A\d+\z/)

      [ (Time.httpdate(value) - Time.current).ceil, 0 ].max
    rescue ArgumentError
      nil
    end

    # Reads at most one byte past the limit, so an oversized or lying entry
    # is caught without inflating it all.
    def unzip(entry)
      limit = Activity::MAXIMUM_FILE_SIZE
      raise InvalidFileError if entry.size > limit

      bytes = entry.get_input_stream.read(limit + 1).to_s.b
      raise InvalidFileError if bytes.bytesize > limit

      bytes
    rescue Zip::Error
      raise InvalidFileError, cause: nil
    end

    def uri(path)
      URI("#{BASE_URL}#{path}")
    end
  end
end
