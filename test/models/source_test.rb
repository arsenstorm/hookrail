require "test_helper"

class SourceTest < ActiveSupport::TestCase
  test "invalid when secret is present but header is blank" do
    source = Source.new(name: "Test", project: create_test_project!, verification: { secret: "x" })
    assert_not source.valid?
    assert_includes source.errors[:verification_header], "can't be blank"
  end

  test "invalid when secret is present and algorithm is unsupported" do
    source = Source.new(name: "Test", project: create_test_project!, verification: { secret: "x", header: "H", algorithm: "md5" })
    assert_not source.valid?
    assert_includes source.errors[:verification_algorithm], "is not included in the list"
  end

  test "blank-string verification values are compacted on validation" do
    source = Source.new(name: "Test", project: create_test_project!, verification: { secret: "x", header: "H", algorithm: "" })
    source.valid?
    assert_not_includes source.verification.keys, "algorithm"
  end

  test "verification_enabled? is false when verification is empty" do
    source = Source.new(name: "Test", project: create_test_project!, verification: {})
    assert_not source.verification_enabled?
  end
end
