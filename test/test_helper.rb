ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"
WebMock.disable_net_connect!(allow_localhost: true)

# WebMock stubs HTTP, not DNS, and Delivery::AddressGuard resolves before it
# connects. Answer from a table instead so the suite needs no network: literal
# addresses pass through, any hostname looks public. Tests that care what a
# host resolves to swap this out themselves.
Delivery::AddressGuard.resolver = lambda do |host|
  IPAddr.new(host)
  [ host ]
rescue IPAddr::Error
  [ "93.184.216.34" ]
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Auth/org scoping: resources now require a project. Build one on demand.
    def create_test_project!
      user = User.create!(github_uid: "test-#{SecureRandom.hex(4)}", github_login: "tester")
      user.ensure_org_and_project!
      user.organization.projects.first
    end

    # Add more helper methods to be used by all tests here...
  end
end
