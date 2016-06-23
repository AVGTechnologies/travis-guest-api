require 'active_support/core_ext/numeric/time'
require 'redis'

module Travis::GuestAPI
  # Remembers steps by their jobs so that
  # they can be  provided in route GET steps/:uuid
  # for backward compatibility.
  class Cache
    def initialize(max_job_time = 24.hours, config = {})
      @max_job_time = max_job_time
      @mutex = Mutex.new
      @redis = Redis.new config || {}
    end

    def set(job_id, step_uuid, result)
      fail ArgumentError, 'Parameter "result" must be a hash' unless
        result.is_a?(Hash)
      job_record = {}
      @mutex.synchronize do
        job_record = get_job(job_id) || {}
        job_record[step_uuid] ||= {}
        job_record[step_uuid].deep_merge!(result)
        set_job(job_id, job_record)
      end

      job_record[step_uuid]
    end

    def set_multiple(job_id, steps)
      fail ArgumentError, 'Parameter "steps" must be an array' unless steps.is_a?(Array)

      @mutex.synchronize do
        job_record = get_job(job_id) || {}

        steps.each do |step|
          step_uuid = step['uuid']

          job_record[step_uuid] ||= {}
          job_record[step_uuid].deep_merge!(step)
        end

        set_job(job_id, job_record)
      end
    end

    def get(job_id, step_uuid)
      job_record = get_job(job_id)
      return nil unless job_record
      job_record[step_uuid]
    end

    def get_result(job_id)
      job_record = get_job(job_id)
      return 'failed' unless job_record

      passed = job_record.all? do |key, step_result|
        ['passed', 'pending'].include? step_result['result']
      end

      return passed ? 'passed' : 'failed'
    end

    def exists?(job_id)
      @redis.exists(job_id)
    end

    def delete(job_id)
      @mutex.synchronize do
        Travis.logger.info "Deleting #{job_id} from cache"
        @redis.del job_id
      end
    end

    # Use only if you will never ever use this class again
    #
    def finalize
      @mutex.synchronize do
        @redis.flushdb
      end
    end

    private

    def get_job(id)
      job_string = @redis.get(id)
      return nil unless job_string
      JSON.parse(job_string)
    end

    def set_job(job_id, job)
      @redis.set(job_id, job.to_json)
      @redis.expire(job_id, @max_job_time)
    end
  end
end
