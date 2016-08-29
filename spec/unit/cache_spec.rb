require 'spec_helper'
require 'travis/guest-api/cache'
require 'travis/support'
require 'active_support/core_ext/numeric/time'
require 'timeout'

describe Travis::GuestAPI::Cache do
  let(:max_job_time) { 5.minutes }
  let(:gc_polling_interval) { 5.minutes }
  let(:cache) { Travis::GuestAPI::Cache.new max_job_time, Travis.config.redis }
  let(:step_uuid) { 'ffdec891-ac4d-4187-a228-3edbe474c775' }

  after(:each) { cache.finalize }

  describe '#set' do
    it 'persists given value' do
      job_id = 42
      result = { 'foo' => 'test result' }
      cache.set job_id, step_uuid, result
      expect(cache.get job_id, step_uuid).to eq result
    end

    it 'performs recusive update' do
      job_id = 42
      cache.set job_id, step_uuid, 'test_data' => { v1: 1 }
      cache.set job_id, step_uuid, 'test_data' => { v2: 2 }
      expect(cache.get job_id, step_uuid).to eq (
        { 'test_data' => { 'v1' => 1, 'v2' => 2 } }
      )
    end

    it 'returns cached value' do
      job_id = 42
      cache.set job_id, step_uuid, { 'test_data' => { 'v1' => 1 } }
      res = cache.set job_id, step_uuid, { 'test_data' => { 'v2' => 2 } }
      expect(res).to eq (
        { 'test_data' => { 'v1' => 1, 'v2' => 2 } }
      )
    end

    it 'throws when result is not a hash' do
      expect do
        cache.set 42, step_uuid, 'not a hash'
      end.to raise_error ArgumentError
    end
  end

  describe '#get_added_step_metrics' do
    let(:job_id) { 42 }
    let(:sample_record) do
      {
        'classname' => 'foo_case_name',
        'position' => 10,
        'class_position' => 11
      }
    end

    let(:sample_record2) do
      {
        'classname' => 'foo_case_name',
        'position' => 10,
        'class_position' => 11,
        'added_step' => true,
        'name' => 'garply_name'
      }
    end

    it 'searches for given job' do
      job_id = 55
      expect(cache).to receive(:get_job) do
        double(
          'fake record',
          values: {}
        )
      end

      expect do
        cache.get_added_step_metrics(job_id, 'foo_case_name', 'bar_step_name')
      end.to raise_error (Travis::GuestAPI::Cache::AddStepException)
    end

    it 'returns correct step_position and class_position' do
      cache.set job_id, 'some uuid', sample_record
      metrics = cache.get_added_step_metrics(job_id, 'foo_case_name', 'bar_step_name')
      expect(metrics).to include('step_position' => 11, 'class_position' => 11)
    end

    it 'raises exception when class is not found in cache' do
      cache.set job_id, 'some uuid', sample_record
      expect do
        cache.get_added_step_metrics(job_id, 'foo_baz_qux_case_name', 'bar_step_name')
      end.to raise_error (Travis::GuestAPI::Cache::AddStepException)
    end

    it 'raises exception when class_position is not found in cache' do
      sample_record = {
        'classname' => 'foo_case_name',
        'position' => 10,
        'class_position_' => 11
      }

      cache.set job_id, 'some uuid', sample_record
      expect do
        cache.get_added_step_metrics(job_id, 'foo_case_name', 'bar_step_name')
      end.to raise_error (Travis::GuestAPI::Cache::AddStepException)
    end

    context 'test case scope' do
      it 'raises exception when step name is already present in cache' do
        cache.set job_id, 'some uuid', sample_record2
        expect do
          cache.get_added_step_metrics(job_id, 'foo_case_name', 'garply_name')
        end.to raise_error (Travis::GuestAPI::Cache::AddStepException)
      end
    end

    context 'job scope' do
      it 'raises exception when step name is already present in cache' do

        sample_record2['name'] = 'qux_name'

        cache.set job_id, 'some uuid', sample_record2

        sample_record = {
          'classname' => 'quux_case_name',
          'position' => 10,
          'class_position' => 11,
          'added_step' => true,
          'name' => 'garply_name'
        }

        cache.set job_id, 'some uuid2', sample_record

        expect do
          cache.get_added_step_metrics(job_id, 'foo_case_name', 'garply_name')
        end.to raise_error (Travis::GuestAPI::Cache::AddStepException)
      end
    end

    it 'does not raise exception when the same static step name is already present in cache' do
      sample_record['name'] = 'garply_name'
      cache.set job_id, 'some uuid', sample_record
      cache.get_added_step_metrics(job_id, 'foo_case_name', 'garply_name')
    end
  end

  describe '#set_multiple' do
    it 'persists given value' do
      job_id = 42
      result = { 'foo' => 'test result', 'uuid' => step_uuid }
      cache.set_multiple job_id, [result]
      expect(cache.get job_id, step_uuid).to eq result
    end

    it 'performs recusive update' do
      job_id = 42
      cache.set_multiple job_id, ['test_data' => { v1: 1 }, 'uuid' => step_uuid]
      cache.set_multiple job_id, ['test_data' => { v2: 2 }, 'uuid' => step_uuid]
      expect(cache.get job_id, step_uuid).to eq (
        { 'test_data' => { 'v1' => 1, 'v2' => 2 }, 'uuid' => step_uuid }
      )
    end

    it 'rewrites value' do
      job_id = 42
      cache.set_multiple job_id, ['test_data' => { v1: 1 }, 'uuid' => step_uuid]
      cache.set_multiple job_id, ['test_data' => { v1: 2 }, 'uuid' => step_uuid]
      expect(cache.get job_id, step_uuid).to eq (
        { 'test_data' => { 'v1' => 2 }, 'uuid' => step_uuid }
      )
    end

    it 'throws when result is not a hash' do
      expect do
        cache.set_multiple 42, step_uuid, 'not a hash'
      end.to raise_error ArgumentError
    end
  end

  describe '#get' do
    context 'record time to live expired' do
      let(:max_job_time) { 0 }
      let(:gc_polling_interval) { 0 }

      it 'returns Nil' do
        job_id = 666
        cache.set job_id, step_uuid, 'foo' => 'bar'
        sleep 0.2
        expect(cache.get job_id, step_uuid).to be_nil
      end
    end

    context 'record alive' do
      it 'returns record' do
        job_id = 666
        record = { 'foo' => 'bar' }
        cache.set job_id, step_uuid, record
        expect(cache.get job_id, step_uuid).to eq record
      end
    end
  end

  describe '#delete' do
    it 'deletes specified record' do
      job_id = 666
      cache.set job_id, step_uuid, foo: 'bar'
      cache.delete job_id
      expect(cache.get job_id, step_uuid).to be_nil
    end
  end

  describe "#exists" do
    it "returns false if job is not cached" do
      expect(cache.exists?(12345)).to be false
    end

    it "return true if job is cached" do
      cache.set 123, step_uuid, {}
      expect(cache.exists?(123)).to be true
    end
  end

  describe "#get_result" do
    it "returns 'failed' when no result set" do
      expect(cache.get_result(123456)).to eq 'failed'
    end

    it "returns 'failed' when any test_step was set (event without result)" do
      cache.set 123, step_uuid, {}
      expect(cache.get_result(123)).to eq 'failed'
    end

    it "returns 'passed' to result values 'passed' and 'pending'" do
      cache.set 123, step_uuid, { 'result' => 'pending'}
      expect(cache.get_result(123)).to eq 'passed'
      cache.set 123, step_uuid, { 'result' => 'passed'}
      expect(cache.get_result(123)).to eq 'passed'
    end

    it "returns 'failed' to result values 'blocked' and 'created'" do
      cache.set 123, step_uuid, { 'result' => 'blocked'}
      expect(cache.get_result(123)).to eq 'failed'
      cache.set 123, step_uuid, { 'result' => 'created'}
      expect(cache.get_result(123)).to eq 'failed'
    end

    it "returns 'failed' when any test_step was failed" do
      cache.set 123, SecureRandom.uuid, { 'result' => 'passed'}
      cache.set 123, SecureRandom.uuid, { 'result' => 'failed'}
      cache.set 123, SecureRandom.uuid, { 'result' => 'passed'}
      expect(cache.get_result(123)).to eq 'failed'
    end
  end
end

