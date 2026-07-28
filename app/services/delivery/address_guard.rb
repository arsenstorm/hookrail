require "ipaddr"
require "socket"

module Delivery
  # Destination URLs are user-supplied and fetched by our servers, and the
  # response body is stored on the attempt for the tenant to read. Without a
  # guard that turns any account into a proxy for our internal network and the
  # cloud metadata service.
  #
  # The check is on the *resolved* address, never the hostname: a public name
  # can resolve to 127.0.0.1, which is how DNS-rebinding SSRF works. Callers
  # pin the returned address (Net::HTTP#ipaddr=) so the connection cannot land
  # somewhere other than what was validated.
  class AddressGuard
    class BlockedError < StandardError; end

    ALLOWED_SCHEMES = %w[http https].freeze

    # Loopback, private, link-local (169.254.169.254 is cloud metadata),
    # carrier-grade NAT, multicast, and the reserved/documentation ranges.
    BLOCKED_RANGES = %w[
      0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16
      172.16.0.0/12 192.0.0.0/24 192.0.2.0/24 192.168.0.0/16 198.18.0.0/15
      198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4
      ::/128 ::1/128 64:ff9b::/96 100::/64 2001:db8::/32 fc00::/7 fe80::/10 ff00::/8
    ].map { |range| IPAddr.new(range) }.freeze

    # Hostnames that are local by definition, rejected without a DNS round trip
    # so the form can say no while the user is still looking at it.
    BLOCKED_HOSTS = %w[localhost].freeze
    BLOCKED_HOST_SUFFIXES = %w[.localhost .local .internal].freeze

    # Swapped out in tests so the suite does not depend on DNS.
    singleton_class.attr_accessor :resolver
    self.resolver = ->(host) {
      Addrinfo.getaddrinfo(host, nil, nil, :STREAM).map(&:ip_address).uniq
    }

    # Syntax-only check for form validation: scheme, host, and any address
    # written as a literal. Does not resolve — `resolve!` is the enforcement.
    def self.check_url!(url)
      uri = URI.parse(url.to_s)
      unless ALLOWED_SCHEMES.include?(uri.scheme)
        raise BlockedError, "URL must start with http:// or https://"
      end

      host = uri.host.to_s.downcase.delete_suffix(".")
      raise BlockedError, "URL must include a host" if host.blank?

      if BLOCKED_HOSTS.include?(host) || BLOCKED_HOST_SUFFIXES.any? { |s| host.end_with?(s) }
        raise BlockedError, "#{host} is a local address"
      end

      literal = parse_address(host)
      if literal && blocked?(literal)
        raise BlockedError, "#{host} is not a public address"
      end

      uri
    rescue URI::InvalidURIError
      raise BlockedError, "URL is not valid"
    end

    # Resolves and returns the public address to connect to. Raises
    # BlockedError when the host resolves only to addresses we refuse to reach.
    def self.resolve!(url)
      uri = check_url!(url)
      host = uri.host.to_s.downcase.delete_suffix(".")

      addresses = begin
        resolver.call(host)
      rescue SocketError, ArgumentError => e
        raise BlockedError, "could not resolve #{host}: #{e.message}"
      end

      allowed = addresses.filter_map { |address| parse_address(address) }
                         .reject { |address| blocked?(address) }
      if allowed.empty?
        raise BlockedError, "#{host} resolves to a blocked address (#{addresses.join(", ")})"
      end

      allowed.first.to_s
    end

    def self.blocked?(address)
      # ::ffff:127.0.0.1 is loopback wearing an IPv6 costume; compare the v4.
      address = address.native if address.ipv4_mapped?
      BLOCKED_RANGES.any? { |range| range.include?(address) }
    end

    def self.parse_address(value)
      IPAddr.new(value.to_s)
    rescue IPAddr::Error
      nil
    end

    private_class_method :parse_address
  end
end
