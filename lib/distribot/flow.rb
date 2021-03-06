
module Distribot
  class NotRunningError < StandardError; end
  class NotPausedError < StandardError; end

  # rubocop:disable ClassLength
  class Flow
    attr_accessor :id, :phases, :consumer, :finished_callback_queue, :created_at, :data

    def initialize(attrs = {})
      self.id = attrs[:id]
      self.created_at = attrs[:created_at] unless attrs[:created_at].nil?
      self.phases = []
      (attrs[:phases] || []).each do |options|
        add_phase(options)
      end
      self.data = attrs[:data]
    end

    def self.active
      redis.smembers('distribot.flows.active').map do |id|
        self.find(id)
      end
    end

    def self.create!(attrs = {})
      new(attrs).save!
    end

    # rubocop:disable Metrics/AbcSize
    def save!(&block)
      fail StandardError, 'Cannot re-save a flow' if id
      self.id = SecureRandom.uuid
      record_id = redis_id + ':definition'
      self.created_at = Time.now.to_f

      # Actually save the record:
      redis.set record_id, serialize

      # Transition into the first phase:
      add_transition to: current_phase, timestamp: Time.now.utc.to_f

      # Add our id to the list of active flows:
      redis.sadd 'distribot.flows.active', id
      redis.incr('distribot.flows.running')

      # Announce our arrival to the rest of the system:
      Distribot.publish! 'distribot.flow.created', flow_id: id

      wait_for_flow_to_finish(block) if block_given?
      self
    end

    def self.find(id)
      redis_id = Distribot.redis_id('flow', id)
      raw_json = redis.get("#{redis_id}:definition") || return
      new(
        JSON.parse(raw_json, symbolize_names: true)
      )
    end

    def add_phase(options = {})
      phases << Phase.new(options)
    end

    def phase(name)
      phases.find { |x| x.name == name }
    end

    def pause!
      fail NotRunningError, 'Cannot pause unless running' unless running?
      add_transition(
        from: current_phase,
        to: 'paused',
        timestamp: Time.now.utc.to_f
      )
    end

    def resume!
      fail NotPausedError, 'Cannot resume unless paused' unless paused?

      # Find the last transition before we were paused:
      prev_phase = transitions.reverse.find { |x| x.to != 'paused' }
      # Back to where we once belonged
      add_transition(
        from: 'paused', to: prev_phase.to, timestamp: Time.now.utc.to_f
      )
    end

    def paused?
      current_phase == 'paused'
    end

    def cancel!
      fail NotRunningError, 'Cannot cancel unless running' unless running?
      add_transition(
        from: current_phase, to: 'canceled', timestamp: Time.now.utc.to_f
      )
      redis.decr 'distribot.flows.running'
      redis.srem 'distribot.flows.active', id
    end

    def canceled?
      current_phase == 'canceled'
    end

    def running?
      ! (paused? || canceled? || finished?)
    end

    def redis_id
      @redis_id ||= Distribot.redis_id('flow', id)
    end

    def transition_to!(phase)
      previous_transition = transitions.last
      prev = previous_transition ? previous_transition[:to] : nil
      add_transition(from: prev, to: phase, timestamp: Time.now.utc.to_f)
      Distribot.publish!(
        'distribot.flow.phase.started',
        flow_id: id,
        phase: phase
      )
    end

    def add_transition(item)
      redis.sadd(redis_id + ':transitions', item.to_json)
    end

    def transitions
      redis.smembers(redis_id + ':transitions').map do |item|
        OpenStruct.new JSON.parse(item, symbolize_names: true)
      end.sort_by(&:timestamp)
    end

    def current_phase
      latest_transition = transitions.last
      if latest_transition
        latest_transition.to
      else
        phases.find(&:is_initial).name
      end
    end

    def next_phase
      current = current_phase
      phases.find { |x| x.name == current }.transitions_to
    end

    def finished?
      phase(transitions.last.to).is_final
    end

    def stubbornly(task, &block)
      loop do
        begin
          return block.call
        rescue NoMethodError => e
          warn "Error during #{task}: #{e} --- #{e.backtrace.join("\n")}"
          sleep 1
        end
      end
    end

    private

    def wait_for_flow_to_finish(block)
      Thread.new do
        loop do
          sleep 1
          if finished? || canceled?
            block.call(flow_id: id)
            break
          end
        end
      end
    end

    def self.redis
      Distribot.redis
    end

    def redis
      self.class.redis
    end

    def serialize
      to_hash.to_json
    end

    def to_hash
      {
        id: id,
        created_at: created_at,
        phases: phases.map(&:to_hash),
        data: self.data
      }
    end
  end
end
