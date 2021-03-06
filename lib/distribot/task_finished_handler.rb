
module Distribot
  class TaskFinishedHandler
    include Distribot::Handler
    subscribe_to 'distribot.flow.task.finished', handler: :callback

    def callback(message)
      task_counter_key = task_counter(message)
      current_value = Distribot.redis.get(task_counter_key) || return
      return unless current_value.to_i == 0
      Distribot.redis.del(task_counter_key)
      announce_handler_has_finished(message)
    end

    def announce_handler_has_finished(message)
      Distribot.publish!(
        'distribot.flow.handler.finished',
        flow_id: message[:flow_id],
        phase: message[:phase],
        handler: message[:handler],
        task_queue: message[:task_queue]
      )
    end

    def task_counter(message)
      # i.e. - distribot.flow.flowId.phaseName.handlerName.finished
      [
        'distribot',
        'flow',
        message[:flow_id],
        message[:phase],
        message[:handler].to_s,
        'finished'
      ].join('.')
    end
  end
end
