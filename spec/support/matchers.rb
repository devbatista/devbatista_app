# expect(body).to include("a").and(exclude("b"))
RSpec::Matchers.define_negated_matcher :exclude, :include
