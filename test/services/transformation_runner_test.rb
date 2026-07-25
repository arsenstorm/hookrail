require "test_helper"

class TransformationRunnerTest < ActiveSupport::TestCase
  def build_event(headers: {}, body: "", path: "/wh", query_string: "")
    Event.new(headers: headers, body: body, path: path, query_string: query_string, http_method: "POST")
  end

  test "JSON body arrives parsed" do
    event = build_event(body: '{"type":"x"}')
    code = <<~JS
      function transform(r) { return { headers: r.headers, body: { wrapped: r.body.type } }; }
    JS

    result = Transformation::Runner.run(code, event)

    assert_equal({ "wrapped" => "x" }, JSON.parse(result[:body]))
  end

  test "non-JSON body arrives as raw string, headers default to empty when omitted" do
    event = build_event(body: "plain")
    code = 'function transform(r) { return { body: r.body + "!" }; }'

    result = Transformation::Runner.run(code, event)

    assert_equal "plain!", result[:body]
    assert_equal({}, result[:headers])
  end

  test "header add returns string values" do
    event = build_event(headers: { "X-Original" => "1" }, body: "plain")
    code = <<~JS
      function transform(r) {
        var headers = r.headers;
        headers["X-Extra"] = "1";
        return { headers: headers, body: r.body };
      }
    JS

    result = Transformation::Runner.run(code, event)

    assert_equal "1", result[:headers]["X-Extra"]
    assert result[:headers].values.all? { |v| v.is_a?(String) }
  end

  test "path and query are visible inputs" do
    event = build_event(body: "plain", path: "/wh/abc", query_string: "x=1")
    code = 'function transform(r) { return { body: r.path + "?" + r.query }; }'

    result = Transformation::Runner.run(code, event)

    assert_equal "/wh/abc?x=1", result[:body]
  end

  test "throwing code raises Transformation::Error with the thrown message" do
    event = build_event(body: "plain")
    code = 'function transform(r) { throw new Error("nope"); }'

    error = assert_raises(Transformation::Error) { Transformation::Runner.run(code, event) }
    assert_match "nope", error.message
  end

  test "non-object return raises transform must return an object" do
    event = build_event(body: "plain")
    code = "function transform(r) { return 42; }"

    error = assert_raises(Transformation::Error) { Transformation::Runner.run(code, event) }
    assert_equal "transform must return an object", error.message
  end

  test "infinite loop raises a timeout error" do
    event = build_event(body: "plain")
    code = "function transform(r) { while (true) {} }"

    error = assert_raises(Transformation::Error) { Transformation::Runner.run(code, event) }
    assert_equal "timed out after 1000ms", error.message
  end

  test "check! requires a transform function and validates syntax" do
    error = assert_raises(Transformation::Error) { Transformation::Runner.check!("var x = 1") }
    assert_equal "must define a transform function", error.message

    assert_raises(Transformation::Error) { Transformation::Runner.check!("function transform(r) {") }

    assert_nothing_raised { Transformation::Runner.check!("function transform(r) { return r; }") }
  end
end
