class Hiiro
  # Raise for expected user-facing failures (bad arguments, missing records).
  # Hiiro#run prints only the message for these, with no backtrace.
  class Error < StandardError; end
end
