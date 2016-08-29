require 'active_support/core_ext/numeric/time'
require 'redis'

module Travis::GuestAPI
  # Remembers steps by their jobs so that
  # they can be  provided in route GET steps/:uuid
  # for backward compatibility.
  class Cache
    class AddStepException < Exception
    end

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

    def get_added_step_metrics(job_id, class_name, added_step_name)
      job_record = get_job(job_id)
      raise AddStepException,
        "Test case #{class_name} could not be found for job id: #{job_id}" if job_record.nil?
      items = job_record.values.select { |obj| obj['classname'] == class_name }

      duplicates = job_record.values.select { |obj| obj['added_step'] == true && obj['name'] == added_step_name }

      raise AddStepException,
        "Step #{added_step_name} was already added, cannot be added twice." if duplicates.any?

      class_index = items.map do |obj|
        obj['class_position'].nil? ? nil : obj['class_position'].to_i
      end.compact.max

      raise AddStepException, "Invalid class_position in cache." if class_index.nil?

      step_index = items.map do |obj|
        obj['position'].to_i if obj['class_position'] && obj['class_position'] == class_index
      end.compact.max

      raise AddStepException, "Invalid class_name: #{class_name}" if items.empty?

      { 'step_position' => step_index + 1, 'class_position' => class_index }
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
