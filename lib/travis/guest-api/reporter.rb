require 'travis/support/logging'

module Travis
  module GuestApi
    # Reporter that streams build logs. Because workers now support multiple types of
    # projects (e.g. Ruby, Clojure) as long as VMs provide all the necessary, log streaming
    # picks routing key dynamically for each build.
    class Reporter
      include Logging

      log_header { "#{name}:log_streamer" }

      attr_reader :name

      def initialize(name, state_publisher, log_publisher, test_result_publisher)
        @name = name
        @state_publisher = state_publisher
        @log_publisher = log_publisher
        @test_result_publisher = test_result_publisher

        @jobs_messages_sizes = {}

        reset
      end

      def reset
        @logs_part_number = 0
      end

      def notify(event, data)
        message(event, data)
      end

      def message(event, data)
        unless publisher_for(event).channel.open?
          warn "trying to publish '#{data}' to closed channel for '#{event}' event"
          return
        end
        if Array === data
          data.each { |d| d.merge!(uuid: Travis.uuid) }
        else
          data = data.merge(uuid: Travis.uuid)
        end
        options = {
          properties: { type: event },
        }
        publisher_for(event).publish(data, options)
      end
      # log :message, :as => :debug, :only => :before
      # this has been disabled as logging is also logged as debug, making the
      # logs super verbose, this can be turned on as needed

      def publisher_for(event)
        return @log_publisher if event.to_s =~ /log/
        return @test_result_publisher if event.to_s =~ /test_result/
        @state_publisher
      end

      def close
        @state_publisher.close
        @log_publisher.close
      end

      # simple helpers
      def send_log(job_id, output, last_message = false)
        @logs_part_number += 1

        @jobs_messages_sizes[job_id] ||= {}
        @jobs_messages_sizes[job_id][:size] ||= 0
        @jobs_messages_sizes[job_id][:size] += output.size

        max_log_size = (Travis.config.max_log_size || 1024*5)

        if @jobs_messages_sizes[job_id][:size] > max_log_size
          if @jobs_messages_sizes[job_id][:message_truncated]
            output = ''
          else
            Travis.logger.info "Messages exceeded limit size: #{max_log_size} for #{job_id}"
            output = "Messages exceeded limit size: #{max_log_size}"
            @jobs_messages_sizes[job_id][:message_truncated] = true
          end
        end

        if output.size > 0 || last_message
          message = { id: job_id, log: output, number: @logs_part_number }
          message[:final] = true if last_message
          notify('job:test:log', message)
        end
      end

      def send_last_log(job_id)
        send_log(job_id, "", true)
      end

      def send_tresult(job_id, payload)
        notify('job:test:test_result', { steps: payload })
      end

      def send_tresult_update(job_id, payload)
        notify('job:test:test_result', { steps: payload })
      end

      def send_last_tresult(job_id)
        notify('job:test:test_result', { job_id: job_id, final: true })
      end

      def notify_job_received(job_id)
        notify('job:test:receive', id: job_id, state: 'received', received_at: Time.now.utc, worker: Travis::GuestApi.config.hostname)
      end

      def notify_job_started(job_id)
        notify('job:test:start', id: job_id, state: 'started', started_at: Time.now.utc)
      end

      def notify_job_finished(job_id, result)
        notify('job:test:finish', id: job_id, state: normalized_state(result), finished_at: Time.now.utc)
      end

      def restart(job_id)
        notify('job:test:reset', id: job_id, state: 'reset')
      end

      def normalized_state(result)
        return result if result.is_a?(String)
        case result
        when 0; 'passed'
        when 1; 'failed'
        when 2; 'errored'
        else    'errored'
        end
      end
    end
  end
end
