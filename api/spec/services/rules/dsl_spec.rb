require "rails_helper"

RSpec.describe Rules::Dsl do
  let(:ctx) { { "item" => { "icms" => { "rate" => "12.00", "amount" => "120.00", "base_amount" => "1000.00" }, "product" => { "cfop" => "5102" } }, "doc" => { "items" => [{ "n" => "1.50" }, { "n" => "2.50" }] }, "params" => { "tol" => "0.01" } } }

  it "resolves paths and absence" do
    expect(Rules::Dsl::Path.fetch(ctx, "item.icms.rate")).to eq("12.00")
    expect(Rules::Dsl::Path.absent?(Rules::Dsl::Path.fetch(ctx, "item.ipi.rate"))).to be true
    expect(Rules::Dsl::Path.fetch(ctx, "doc.items[1].n")).to eq("2.50")
  end

  it "evaluates comparisons numerically" do
    expect(Rules::Dsl::Condition.evaluate({ "field" => "item.icms.rate", "op" => "eq", "value" => "12" }, ctx)).to be true
    expect(Rules::Dsl::Condition.evaluate({ "field" => "item.icms.rate", "op" => "gt", "value" => 7 }, ctx)).to be true
    expect(Rules::Dsl::Condition.evaluate({ "field" => "item.icms.amount", "op" => "approx", "value" => { "calc" => "item.icms.base_amount * item.icms.rate / 100" }, "tolerance" => { "param" => "tol" } }, ctx)).to be true
    expect(Rules::Dsl::Condition.evaluate({ "field" => "item.product.cfop", "op" => "starts_with", "value" => "5" }, ctx)).to be true
  end

  it "handles absent fields safely" do
    expect(Rules::Dsl::Condition.evaluate({ "field" => "item.ipi.rate", "op" => "absent" }, ctx)).to be true
    expect { Rules::Dsl::Condition.evaluate({ "field" => "item.ipi.rate", "op" => "gt", "value" => 1 }, ctx) }.to raise_error(Rules::EvaluationError)
  end

  it "evaluates calc with functions and sum" do
    expect(Rules::Dsl::Calc.evaluate("round(1000 * (1 - 33.33 / 100), 2)", ctx)).to eq(BigDecimal("666.70"))
    expect(Rules::Dsl::Calc.evaluate("sum(doc.items.n)", ctx)).to eq(BigDecimal("4.00"))
    expect(Rules::Dsl::Calc.evaluate("item.icms.rate >= 12 and not (item.icms.rate > 12)", ctx)).to be true
    expect { Rules::Dsl::Calc.evaluate("system('x')", ctx) }.to raise_error(Rules::EvaluationError)
  end

  it "evaluates quantifiers" do
    expect(Rules::Dsl::Condition.evaluate({ "every" => "doc.items", "as" => "i", "where" => { "field" => "i.n", "op" => "gt", "value" => 1 } }, ctx)).to be true
    expect(Rules::Dsl::Condition.evaluate({ "count" => "doc.items", "where" => { "field" => "it.n", "op" => "gt", "value" => 2 }, "op" => "eq", "value" => 1 }, ctx)).to be true
  end

  it "renders templates" do
    expect(Rules::Dsl::Template.render("rate {{item.icms.rate}} / {{item.ipi.rate}}", ctx)).to eq("rate 12.00 / —")
  end
end
