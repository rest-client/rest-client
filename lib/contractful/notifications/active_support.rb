# frozen_string_literal: true

# Optional bridge from contractful's internal notification hub to
# ActiveSupport::Notifications (the Rails-ecosystem standard). Loading this
# file — never loaded by <tt>require 'contractful'</tt> — forwards every
# {Contractful::Notifications} event to AS::Notifications so Rails
# subscribers, LogSubscribers and APM agents receive them natively:
#
#   require 'contractful'
#   require 'contractful/notifications/active_support'
#
#   ActiveSupport::Notifications.subscribe(/^contractful\./) do |*args|
#     event = ActiveSupport::Notifications::Event.new(*args)
#     Rails.logger.info "#{event.name} #{event.payload.inspect} (#{event.duration}ms)"
#   end
#
# Each event is forwarded as <tt>contractful.<name></tt> with the event
# payload as instrument payload (plus the monotonic <tt>:at</tt> timestamp).
# Unsubscribe from the internal hub with
# <tt>Contractful::Notifications.clear!</tt> to detach the bridge.
#
# Requires the +activesupport+ gem (>= 6.0) at load time; it is an optional
# integration and never a runtime dependency of the gem itself.

# 'active_support' rather than just 'active_support/notifications': since
# ActiveSupport 7.1 the notifications module depends on
# IsolatedExecutionState and friends and is not self-sufficient standalone.
begin
  require 'active_support'
rescue LoadError => e
  raise LoadError,
        "contractful's ActiveSupport bridge requires the activesupport gem " \
        "(add `gem 'activesupport'` to your Gemfile): #{e.message}"
end

Contractful::Notifications.subscribe do |event|
  ActiveSupport::Notifications.instrument(
    "contractful.#{event[:name]}", **event[:payload], at: event[:at]
  )
end
