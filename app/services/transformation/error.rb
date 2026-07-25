module Transformation
  # Own file so Zeitwerk can load Transformation::Error without Runner having
  # been referenced first.
  class Error < StandardError; end
end
