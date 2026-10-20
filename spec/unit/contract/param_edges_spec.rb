# frozen_string_literal: true

require_relative '../../spec_helper'

# Edge-branch coverage for Param coercion and constraint enforcement: the
# failure paths of bounds checking, Float/boolean/class coercion and the
# Kernel-cast fallback. Complements the happy paths in param_spec.rb.
RSpec.describe Contractful::Contract::Param do
  def process(value, type = nil, **options)
    described_class.new(:x, type, **options).process!(value)
  end

  describe 'min/max enforcement' do
    it 'rejects a min constraint on a value that cannot be compared' do
      expect { process(Object.new, Object, min: 3) }.to raise_error(
        Contractful::Contract::InvalidParam, /cannot enforce min 3 on Object/
      )
    end

    it 'rejects a max constraint on a value that cannot be compared' do
      expect { process(Object.new, Object, max: 3) }.to raise_error(
        Contractful::Contract::InvalidParam, /cannot enforce max 3 on Object/
      )
    end

    it 'wraps comparison errors raised by exotic comparables' do
      dodgy = Class.new do
        def <(_other)
          raise ArgumentError, 'nope'
        end
      end
      expect { process(dodgy.new, dodgy, min: 3) }.to raise_error(
        Contractful::Contract::InvalidParam, /cannot compare .* with min 3/
      )
    end

    it 'reports values below the minimum and above the maximum' do
      expect { process(1, Integer, min: 2) }.to raise_error(
        Contractful::Contract::InvalidParam, /below minimum 2/
      )
      expect { process(3, Integer, max: 2) }.to raise_error(
        Contractful::Contract::InvalidParam, /above maximum 2/
      )
    end
  end

  describe 'Float coercion' do
    it 'coerces Integers and numeric Strings' do
      expect(process(2, Float)).to eq 2.0
      expect(process('2.5', Float)).to eq 2.5
    end

    it 'rejects non-numeric Strings and unsupported values' do
      expect { process('soon', Float) }.to raise_error(Contractful::Contract::InvalidParam, /expected Float/)
      expect { process([], Float) }.to raise_error(Contractful::Contract::InvalidParam, /expected Float/)
    end
  end

  describe 'boolean coercion' do
    it 'accepts case-insensitive string forms and 1/0 integers' do
      expect(process('TRUE', :boolean)).to be true
      expect(process('no', :boolean)).to be false
      expect(process(1, :boolean)).to be true
      expect(process(0, :boolean)).to be false
    end

    it 'rejects anything else' do
      expect { process('perhaps', :boolean) }.to raise_error(Contractful::Contract::InvalidParam, /expected boolean/)
      expect { process(2, :boolean) }.to raise_error(Contractful::Contract::InvalidParam, /expected boolean/)
    end

    it 'enforces strict booleans under coerce: false' do
      expect { process(nil, :boolean, coerce: false) }.to raise_error(
        Contractful::Contract::InvalidParam, /expected boolean/
      )
    end
  end

  describe 'custom Proc coercion' do
    it 'wraps a failing coercion in InvalidParam' do
      boom = ->(_v) { raise ArgumentError, 'nope' }
      expect { process(1, boom) }.to raise_error(
        Contractful::Contract::InvalidParam, /custom coercion failed: ArgumentError: nope/
      )
    end

    it 'reports the proc in type_name' do
      expect(described_class.new(:x, ->(v) { v }).send(:type_name)).to eq 'custom coercion'
    end
  end

  describe 'class coercion' do
    let(:wraps) do
      Class.new do
        def self.contractful_coerce(_value)
          raise 'cannot'
        end
      end
    end

    it 'wraps a failing contractful_coerce in InvalidParam' do
      expect { process(1, wraps) }.to raise_error(
        Contractful::Contract::InvalidParam, /custom coercion failed: RuntimeError: cannot/
      )
    end

    it 'falls back to a Kernel cast for non-special classes' do
      expect(process('1/2', Rational)).to eq Rational(1, 2)
    end

    it 'rejects values no class-specific path can cast' do
      anon = Class.new
      expect { process('x', anon) }.to raise_error(Contractful::Contract::InvalidParam, /expected/)
    end

    it 'names anonymous classes defensively' do
      anon = Class.new
      expect(described_class.new(:x, anon).send(:type_name)).to eq 'anonymous class'
    end
  end

  describe 'unsupported types' do
    it 'guards the coercion fall-through for types definition validation rejects' do
      # A String instance can never reach normal construction (validate_definition!
      # rejects it), so the coercion switch's else branch is only reachable by
      # injecting the state — that is exactly what this example pins.
      param = described_class.allocate
      param.instance_variable_set(:@name, :x)
      param.instance_variable_set(:@type, 'String')
      param.instance_variable_set(:@coerce, true)
      param.instance_variable_set(:@inclusion, nil)
      param.instance_variable_set(:@min, nil)
      param.instance_variable_set(:@max, nil)
      param.instance_variable_set(:@length, nil)
      param.instance_variable_set(:@pattern, nil)
      expect { param.process!(1) }.to raise_error(Contractful::Contract::InvalidParam, /unsupported type/)
    end
  end
end
