require 'rails_helper'

RSpec.describe Whatsapp::EmbeddedController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  before do
    sign_in user
    Current.account = account
  end

  describe 'GET #new' do
    before do
      allow(ENV).to receive(:fetch).with('WHATSAPP_APP_ID').and_return('test_app_id')
      allow(ENV).to receive(:fetch).with('WHATSAPP_CONFIG_ID', 'test_app_id').and_return('test_config_id')
    end

    it 'returns success status' do
      get :new
      expect(response).to have_http_status(:success)
    end

    it 'returns the correct JSON response' do
      get :new
      
      json_response = JSON.parse(response.body)
      expect(json_response).to include(
        'status' => 'ready',
        'app_id' => 'test_app_id',
        'config_id' => 'test_config_id'
      )
    end
  end

  describe 'GET #callback' do
    let(:code) { 'auth_code_123' }

    context 'with valid authorization code' do
      it 'queues the background job' do
        expect(Whatsapp::EmbeddedSignupJob).to receive(:perform_later)
          .with(account_id: account.id, code: code)
          .and_return(double(job_id: 'job_123'))

        get :callback, params: { code: code }
      end

      it 'returns processing status' do
        allow(Whatsapp::EmbeddedSignupJob).to receive(:perform_later)
          .and_return(double(job_id: 'job_123'))

        get :callback, params: { code: code }

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response).to include(
          'status' => 'processing',
          'job_id' => 'job_123',
          'message' => 'WhatsApp signup is being processed'
        )
      end
    end

    context 'without authorization code' do
      it 'returns bad request status' do
        get :callback

        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body)
        expect(json_response).to include('error' => 'Authorization code is required')
      end
    end

    context 'with error parameter' do
      it 'returns unprocessable entity status' do
        get :callback, params: { error: 'access_denied', error_description: 'User denied access' }

        expect(response).to have_http_status(:unprocessable_entity)
        json_response = JSON.parse(response.body)
        expect(json_response).to include(
          'error' => 'WhatsApp signup failed',
          'message' => 'User denied access'
        )
      end

      it 'logs the error' do
        expect(Rails.logger).to receive(:error)
          .with('WhatsApp embedded signup error: access_denied - User denied access')

        get :callback, params: { error: 'access_denied', error_description: 'User denied access' }
      end
    end

    context 'when job creation fails' do
      before do
        allow(Whatsapp::EmbeddedSignupJob).to receive(:perform_later).and_raise(StandardError, 'Job failed')
      end

      it 'returns internal server error' do
        get :callback, params: { code: code }

        expect(response).to have_http_status(:internal_server_error)
        json_response = JSON.parse(response.body)
        expect(json_response).to include(
          'error' => 'Internal server error',
          'message' => 'Job failed'
        )
      end

      it 'logs the error' do
        expect(Rails.logger).to receive(:error)
          .with('WhatsApp embedded signup callback error: Job failed')

        get :callback, params: { code: code }
      end
    end
  end

  describe 'authorization' do
    context 'when user is not authenticated' do
      before { sign_out user }

      it 'redirects to login for new action' do
        get :new
        expect(response).to have_http_status(:redirect)
      end

      it 'redirects to login for callback action' do
        get :callback, params: { code: 'test_code' }
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when user cannot update account' do
      let(:restricted_user) { create(:user) }
      let(:other_account) { create(:account) }

      before do
        sign_out user
        sign_in restricted_user
        Current.account = other_account
      end

      it 'raises authorization error for new action' do
        expect { get :new }.to raise_error(Pundit::NotAuthorizedError)
      end

      it 'raises authorization error for callback action' do
        expect { get :callback, params: { code: 'test_code' } }.to raise_error(Pundit::NotAuthorizedError)
      end
    end
  end
end