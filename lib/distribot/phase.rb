
module Distribot
  class Phase
    attr_accessor :id,
                  :name,
                  :is_initial,
                  :is_final,
                  :transitions_to,
                  :on_error_transition_to,
                  :handlers

    def initialize(attrs={})
      attrs.each do |key,val|
        next if key.to_s == 'handlers'
        self.send("#{key}=", val)
      end
      self.name = name
      self.handlers = [ ]
      attrs[:handlers] ||= [ ]
      attrs[:handlers].each do |handler|
        if handler.is_a? Hash
          self.handlers.push( PhaseHandler.new handler )
        else
          self.handlers.push( PhaseHandler.new name: handler )
        end
      end
    end

    def to_hash
      {
        id: self.id,
        name: self.name,
        is_initial: self.is_initial || false,
        is_final: self.is_final || false,
        transitions_to: self.transitions_to,
        on_error_transition_to: self.on_error_transition_to,
        handlers: self.handlers || [ ]
      }
    end

  end
end
