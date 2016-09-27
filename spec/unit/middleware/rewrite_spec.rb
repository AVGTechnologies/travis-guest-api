require 'spec_helper'
require 'rack/test'
require 'travis/guest-api/app/middleware/rewrite'

describe Travis::GuestApi::App::Middleware::Rewrite do

  include Rack::Test::Methods

  def app
    Travis::GuestApi::App.new(job_id, reporter, &callback)
  end

  let(:job_id) { 42 }
  let(:reporter) { double(:reporter) }
  let(:callback) { ->(x) { } }

  context "server is run without job_id" do
    let(:job_id) { nil }
    it 'rewrites job_id to rack environment' do
      job_id_URL_param = 42
      get "/api/v1/jobs/#{job_id_URL_param}/uptime"
      expect(last_request.env['job_id']).to eq(job_id_URL_param)
      expect(last_response.status).to eq 200
    end
  end

  context "server is run with job_id 42" do
    let(:job_id) { 42 }
    it 'responds with 422 on job_id mismatch' do
      get "/api/v1/jobs/666/uptime"
      expect(last_response.status).to eq(422)
    end
  end

  describe 'POST /machines/logs/message' do
    let!(:job_id) { 42 }
    it 'rewrites logs route' do
      expected_message = 'test message'
      expect(reporter).to receive(:send_log).with(job_id, expected_message)
      post "/api/v1/machines/logs/message",
        { messageText: expected_message },
        'HTTP_JOBID' => job_id
      expect(last_request.form_data?).to be true
      expect(last_response.status).to eq(200)
    end

    it 'responds with 422 if MachineId not specified' do
      response = post "/api/v1/machines/logs/message", messageText: "foo"
      expect(response.status).to eq(422)
    end
  end

  describe 'POST /api/v1/machines/logs/attachement' do
    TEST_FILE_PATH = File.dirname(__FILE__) + "/../../../README.md"
    test_file = Rack::Test::UploadedFile.new(TEST_FILE_PATH)

    it 'rewrites attachment route' do
      post "/api/v1/machines/logs/attachement",
        localTime: '15:42 8/13/2015',
        indent: 666,
        file: test_file,
        jobId: 42

      expect(last_request.env["CONTENT_TYPE"]).to include("multipart/form-data;")
      expect(last_response.status).to eq(302)
    end
  end

  describe 'POST /machines/networks' do
    it 'rewrites networks route' do
      post "/api/v1/machines/networks"
      expect(last_response.status).to eq(501)
    end
  end

  describe 'POST /machines/steps' do

    it 'returns 422 if machine id not specified' do
      request = {
        stepStack: ['test_case_is_second_last','test_step_is_last'],
        result: 'a big failure',
        classname: 'test_class', # classname = testcase
        position: 555,
        class_position: 666
      }

      post '/api/v1/machines/steps',
      request.to_json,
      { "CONTENT_TYPE" => "application/json" }

      expect(last_response.status).to eq(422)
    end

    it 'returns 422 if step name not specified' do
      request = {
        stepStack: [],
        result: 'a big failure',
        position: 555,
        class_position: 666,
      }

      post '/api/v1/machines/steps',
        request,
        'HTTP_JOBID' => job_id

      expect(last_response.status).to eq(422)
    end

    it 'returns 422 if stepStack is not an array' do
      request = {
        stepStack: 'not an array',
        result: 'a big failure'
      }

      post '/api/v1/machines/steps',
        request,
        'HTTP_JOBID' => job_id

      expect(last_response.status).to eq(422)
    end

    it 'rewrites step to name' do
      request = {
        stepStack: ['test_case_is_second_last','test_step_is_last'],
        result: 'a big success',
        position: 555,
        class_position: 666,
      }

      expect(reporter).to receive(:send_tresult)

      post '/api/v1/machines/steps',
        request,
        'HTTP_JOBID' => job_id

      expect(last_response.status).to eq(200)
      expect(last_request.params['name']).to eq(request[:stepStack].last)
    end

    it 'rewrites test case to classname' do
      request = {
        stepStack: ['test_case_is_second_last','test_step_is_last'],
        result: 'a big success',
        position: 555,
        class_position: 666,
      }

      expect(reporter).to receive(:send_tresult)

      post '/api/v1/machines/steps',
        request,
        'HTTP_JOBID' => job_id

      expect(last_request.params['classname']).to eq(request[:stepStack][-2])
    end

  end
end
