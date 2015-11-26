
# Distribot

A distributed workflow engine for rabbitmq.

![robot](https://cdn2.iconfinder.com/data/icons/windows-8-metro-style/512/robot.png)

## Installation

### In your Gemfile

```ruby
gem 'distribot', git: 'git@github.com:jdrago999/distribot.git'
```

## Usage

```ruby
require 'distribot'

Distribot.configure do |config|
  # Consider using environment variables instead of hard-coding these values.
  # For ideas, look at the excellent 'dotenv' gem.
  config.rabbitmq_url = 'amqp://username:password@your.hostname.com:5762'
  config.redis_url = 'redis://your.redis.hostname:6379/0'
end
```

## The Big Idea

**Workflow:**
  * inserts a message into the 'is_initial' phase's queue.
  * waits for a message on the [PhaseName]Finished queue.
    * when a message is received, transitions the workflow to the next phase.
      * stores the new phase in its db record as 'current phase'
      * adds a transition record to the workflow's transitions table
      * inserts a message into the next phase's queue. (or finishes the workflow if the current phase is_final).

**Phases:**
  * have their own queues
  * can run on one or more instances
  * on enter phase:
    * inserts jobs into each of its handlers' queues
    * then starts listening to the phase's job-finished queue.

**[PhaseName]JobFinished Handler:**
  * checks to see if all of its handlers' queues are empty.
    * if they are, then it inserts a message into the [PhaseName]Finished queue.
      : {status: success, phase: my-phase-name, started_at: X'oclock, finished_at: Y'oclock}

**Handlers:**
  * have their own queues
  * can run together or separately on one or more instances
  * after each message, announces in a finished queue that it has completed a job

```json
{
  "name": "search",
  "phases": [
    {
      "name": "pending",
      "is_initial": true,
      "transitions_to": "searching",
      "on_error_transition_to": "error"
    },
    {
      "name": "searching",
      "transitions_to": "fetching-pages",
      "on_error_transition_to": "error",
      "handlers": [
        "GoogleSearcher"
      ]
    },
    {
      "name": "fetching-pages",
      "transitions_to": "finished",
      "on_error_transition_to": "error",
      "handlers": [
        "PageDownloader"
      ]
    },
    {
      "name": "error",
      "is_final": true,
      "handlers": [
        "ErrorEmailer"
      ]
    },
    {
      "name": "finished",
      "is_final": true,
      "handlers": [
        "JobFinisher"
      ]
    }
  ]
}
```


## Queues:

  * distribot.workflow.created (global)
    * transition to next phase

  * distribot.workflow.phase.started
    * enqueue jobs for handlers in their respective queues
      * we set a counter value in redis to indicate the number of total tasks for each handler.
    * announce in distribot.workflow.tasks.enqueued that we should be waiting for them to finish by listening to queues X and Y

  * distribot.workflow.tasks.enqueued
    * messages contain:
      * the names of the queues ($QUEUE_X, $QUEUE_Y) that the tasks were inserted into
      * how many tasks should be completed
      * starts listening to distribot.workflow.task.finished

  * distribot.workflow.$WORKFLOW_ID.phase.$PHASE_NAME.$HANDLER_NAME.tasks
    * contains JSON messages which describe individual tasks for a given handler.
    * workers subscribe, perform the task, and mark each task as complete by sending a message to distribot.workflow.task.finished

  * distribot.workflow.task.finished
    * told that another task has finished for a phase? a handler?
    * decrements the counter value in redis
    * when the counter value reaches zero then announce in distribot.workflow.phase.finished

  * distribot.workflow.phase.finished
    * if we can move forward, then transition to next phase
    * if we cannot, then msg distribot.workflow.finished

  * distribot.workflow.finished (global)
    * ping the calling system to let it know that the workflow has finished.




