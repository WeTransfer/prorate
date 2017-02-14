require 'spec_helper'

describe Prorate::NullLogger do

  it 'accepts calls that a Logger would' do
    subject = described_class

    subject.debug("foo")
    subject.debug { "foo" }
    subject.debug("progname") { "foo" }

    subject.info("foo")
    subject.info { "foo" }
    subject.info("progname") { "foo" }

    subject.warn("foo")
    subject.warn { "foo" }
    subject.warn("progname") { "foo" }

    subject.error("foo")
    subject.error { "foo" }
    subject.error("progname") { "foo" }

    subject.fatal("foo")
    subject.fatal { "foo" }
    subject.fatal("progname") { "foo" }

    subject.unknown("foo")
    subject.unknown { "foo" }
    subject.unknown("progname") { "foo" }
  end
end
