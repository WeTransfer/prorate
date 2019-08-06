module Prorate
  module NullLogger
    def self.debug(*); end

    def self.info(*); end

    def self.warn(*); end

    def self.error(*); end

    def self.fatal(*); end

    def self.unknown(*); end
  end
end
