
module Distribot

  class PhaseStartedHandler
    include Distribot::Handler
    subscribe_to 'distribot.workflow.phase.started', handler: :callback

    def callback(message)
      workflow = Distribot::Workflow.find( message[:workflow_id] )
      phase = workflow.phase(message[:phase])
      if phase.handlers.empty?
        Distribot.publish! 'distribot.workflow.phase.finished', {
          workflow_id: workflow.id,
          phase: phase.name
        }
      else
        phase.handlers.each do |handler|
puts "#{handler}.ENQUEUE NOW ******************************"
          enumerate_queue = "distribot.workflow.handler.#{handler}.enumerate"
          process_queue = "distribot.workflow.handler.#{handler}.process"
          task_queue = "distribot.workflow.#{workflow.id}.#{phase.name}.#{handler}.tasks"
          finished_queue = "distribot.workflow.#{workflow.id}.#{phase.name}.#{handler}.finished"
          cancel_consumer_queue = "distribot.workflow.#{workflow.id}.#{phase.name}.#{handler}.cancel-consumers"

          Distribot.publish! enumerate_queue, {
            workflow_id: workflow.id,
            phase: phase.name,
            task_queue: task_queue,
            finished_queue: finished_queue,
            cancel_consumer_queue: cancel_consumer_queue
          }
          Distribot.broadcast! process_queue, {
            workflow_id: workflow.id,
            phase: phase.name,
            task_queue: task_queue,
            finished_queue: finished_queue,
            cancel_consumer_queue: cancel_consumer_queue
          }
        end
      end
    end
  end

end
