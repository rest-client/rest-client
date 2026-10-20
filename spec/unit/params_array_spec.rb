# frozen_string_literal: true

require_relative '_lib'

describe Contractful::ParamsArray do
  describe '.new' do
    it 'accepts various types of containers' do
      as_array = [[:foo, 123], [:foo, 456], [:bar, 789], [:empty, nil]]
      [
        [[:foo, 123], [:foo, 456], [:bar, 789], [:empty, nil]],
        [{ foo: 123 }, { foo: 456 }, { bar: 789 }, { empty: nil }],
        [{ foo: 123 }, { foo: 456 }, { bar: 789 }, { empty: nil }],
        [{ foo: 123 }, [:foo, 456], { bar: 789 }, { empty: nil }],
        [{ foo: 123 }, [:foo, 456], { bar: 789 }, [:empty]]
      ].each do |input|
        expect(Contractful::ParamsArray.new(input).to_a).to eq as_array
      end

      expect(Contractful::ParamsArray.new([]).to_a).to eq []
      expect(Contractful::ParamsArray.new([]).empty?).to eq true
    end

    it 'rejects various invalid input' do
      expect do
        Contractful::ParamsArray.new([[]])
      end.to raise_error(IndexError)

      expect do
        Contractful::ParamsArray.new([[1, 2, 3]])
      end.to raise_error(ArgumentError)

      expect do
        Contractful::ParamsArray.new([1, 2, 3])
      end.to raise_error(NoMethodError)
    end
  end
end
