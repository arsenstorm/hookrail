require "test_helper"

class Delivery::AddressGuardTest < ActiveSupport::TestCase
  Blocked = Delivery::AddressGuard::BlockedError

  def with_resolver(map)
    previous = Delivery::AddressGuard.resolver
    Delivery::AddressGuard.resolver = ->(host) { map.fetch(host) }
    yield
  ensure
    Delivery::AddressGuard.resolver = previous
  end

  # --- scheme and syntax ---

  test "rejects non-http schemes" do
    %w[file:///etc/passwd gopher://example.com ftp://example.com javascript:alert(1)].each do |url|
      assert_raises(Blocked, url) { Delivery::AddressGuard.check_url!(url) }
    end
  end

  test "accepts http and https" do
    assert Delivery::AddressGuard.check_url!("http://example.com/hook")
    assert Delivery::AddressGuard.check_url!("https://example.com/hook")
  end

  # --- literal addresses, no DNS ---

  test "rejects literal loopback, private, and link-local addresses" do
    [
      "http://127.0.0.1/x", "http://127.1.1.1/x", "http://[::1]/x",
      "http://10.0.0.5/x", "http://172.16.4.4/x", "http://192.168.1.10/x",
      "http://169.254.169.254/latest/meta-data/", "http://[fe80::1]/x",
      "http://[fc00::1]/x", "http://0.0.0.0/x", "http://100.64.0.1/x"
    ].each do |url|
      assert_raises(Blocked, url) { Delivery::AddressGuard.check_url!(url) }
    end
  end

  test "rejects loopback written as an ipv4-mapped ipv6 address" do
    assert_raises(Blocked) { Delivery::AddressGuard.check_url!("http://[::ffff:127.0.0.1]/x") }
  end

  # 6to4 and Teredo carry an IPv4 address inside the v6 one, so these are
  # 127.0.0.1 and 10.0.0.1 in a costume the v4 range check never sees.
  test "rejects private addresses tunnelled through 6to4 and Teredo" do
    assert_raises(Blocked) { Delivery::AddressGuard.check_url!("http://[2002:7f00:1::]/x") }
    assert_raises(Blocked) { Delivery::AddressGuard.check_url!("http://[2001::a00:1]/x") }
  end

  test "rejects hostnames that are local by definition" do
    %w[http://localhost/x http://app.localhost/x http://db.internal/x http://printer.local/x].each do |url|
      assert_raises(Blocked, url) { Delivery::AddressGuard.check_url!(url) }
    end
  end

  test "allows a literal public address" do
    assert Delivery::AddressGuard.check_url!("http://93.184.216.34/x")
  end

  # --- resolution: the rebinding case ---

  test "rejects a public hostname that resolves to loopback" do
    with_resolver("evil.example" => [ "127.0.0.1" ]) do
      error = assert_raises(Blocked) { Delivery::AddressGuard.resolve!("http://evil.example/x") }
      assert_match "blocked address", error.message
    end
  end

  test "rejects a public hostname that resolves to cloud metadata" do
    with_resolver("metadata.example" => [ "169.254.169.254" ]) do
      assert_raises(Blocked) { Delivery::AddressGuard.resolve!("https://metadata.example/x") }
    end
  end

  test "returns the public address to pin" do
    with_resolver("hooks.example" => [ "93.184.216.34" ]) do
      assert_equal "93.184.216.34", Delivery::AddressGuard.resolve!("https://hooks.example/x")
    end
  end

  test "skips blocked addresses when a host resolves to several" do
    with_resolver("mixed.example" => [ "127.0.0.1", "93.184.216.34" ]) do
      assert_equal "93.184.216.34", Delivery::AddressGuard.resolve!("https://mixed.example/x")
    end
  end

  test "reports a resolution failure as blocked rather than raising SocketError" do
    previous = Delivery::AddressGuard.resolver
    Delivery::AddressGuard.resolver = ->(_host) { raise SocketError, "nodename nor servname provided" }
    assert_raises(Blocked) { Delivery::AddressGuard.resolve!("https://nope.example/x") }
  ensure
    Delivery::AddressGuard.resolver = previous
  end
end
