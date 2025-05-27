require 'rails_helper'

RSpec.describe Whatsapp::EmbeddedSignupService do
  let(:account) { create(:account) }
  let(:code) { 'auth_code_123' }
  let(:service) { described_class.new(account: account, code: code) }
  let(:access_token) { 'access_token_456' }
  let(:waba_id) { '123456789' }
  let(:phone_number_id) { '987654321' }
  let(:business_name) { 'Test Business' }
  let(:phone_number) { '+1234567890' }

  before do
    allow(ENV).to receive(:fetch).with('WHATSAPP_APP_ID').and_return('app_id_123')
    allow(ENV).to receive(:fetch).with('WHATSAPP_APP_SECRET').and_return('app_secret_456')
    allow(ENV).to receive(:fetch).with('FRONTEND_URL', 'localhost:3000').and_return('https://test.example.com')
  end

  describe '#perform' do
    let(:token_exchange_response) do
      instance_double(Faraday::Response, success?: true, body: { access_token: access_token }.to_json)
    end

    let(:debug_token_response) do
      instance_double(
        Faraday::Response,
        success?: true,
        body: {
          data: {
            granular_scopes: [
              { scope: 'whatsapp_business_management', target_ids: [waba_id] }
            ]
          }
        }.to_json
      )
    end

    let(:business_info_response) do
      instance_double(Faraday::Response, success?: true, body: { name: business_name }.to_json)
    end

    let(:phone_numbers_response) do
      instance_double(
        Faraday::Response,
        success?: true,
        body: {
          data: [
            {
              id: phone_number_id,
              display_phone_number: phone_number,
              code_verification_status: 'VERIFIED'
            }
          ]
        }.to_json
      )
    end

    let(:webhook_setup_response) do
      instance_double(Faraday::Response, success?: true, body: { success: true }.to_json)
    end

    before do
      allow(Faraday).to receive(:post).with(
        'https://graph.facebook.com/v21.0/oauth/access_token',
        anything,
        anything
      ).and_return(token_exchange_response)

      allow(Faraday).to receive(:get).with(
        'https://graph.facebook.com/v21.0/debug_token',
        anything
      ).and_return(debug_token_response)

      allow(Faraday).to receive(:get).with(
        "https://graph.facebook.com/v21.0/#{waba_id}",
        anything
      ).and_return(business_info_response)

      allow(Faraday).to receive(:get).with(
        "https://graph.facebook.com/v21.0/#{waba_id}/phone_numbers",
        anything
      ).and_return(phone_numbers_response)

      allow(Faraday).to receive(:post).with(
        "https://graph.facebook.com/v21.0/#{waba_id}/subscribed_apps",
        anything,
        anything
      ).and_return(webhook_setup_response)

      allow(Faraday).to receive(:post).with(
        "https://graph.facebook.com/v21.0/#{waba_id}/webhook",
        anything,
        anything
      ).and_return(webhook_setup_response)
    end

    context 'when successful' do
      it 'creates a new WhatsApp channel' do
        expect { service.perform }.to change(Channel::Whatsapp, :count).by(1)
      end

      it 'returns the created channel' do
        channel = service.perform
        expect(channel).to be_a(Channel::Whatsapp)
        expect(channel.phone_number).to eq(phone_number)
        expect(channel.provider).to eq('whatsapp_cloud')
        expect(channel.account).to eq(account)
      end

      it 'stores provider config correctly' do
        channel = service.perform
        config = channel.provider_config

        expect(config['phone_number_id']).to eq(phone_number_id)
        expect(config['business_account_id']).to eq(waba_id)
        expect(config['api_key']).to eq(access_token)
        expect(config['webhook_verify_token']).to be_present
      end

      it 'logs progress messages' do
        expect(Rails.logger).to receive(:tagged).with('WHATSAPP').at_least(:once).and_yield
        expect(Rails.logger).to receive(:info).with("Starting embedded signup for account #{account.id}")
        expect(Rails.logger).to receive(:info).with("Retrieved WABA: #{waba_id}, Phone: #{phone_number_id}")
        expect(Rails.logger).to receive(:info).with(a_string_matching(/Successfully created\/updated channel/))

        service.perform
      end
    end

    context 'when updating existing channel' do
      let!(:existing_channel) do
        create(:channel_whatsapp, account: account, phone_number: phone_number)
      end

      it 'updates the existing channel instead of creating new one' do
        expect { service.perform }.not_to change(Channel::Whatsapp, :count)
      end

      it 'updates the provider config' do
        service.perform
        existing_channel.reload

        expect(existing_channel.provider_config['phone_number_id']).to eq(phone_number_id)
        expect(existing_channel.provider_config['business_account_id']).to eq(waba_id)
        expect(existing_channel.provider_config['api_key']).to eq(access_token)
      end
    end

    context 'when token exchange fails' do
      let(:token_exchange_response) do
        instance_double(Faraday::Response, success?: false, body: 'Token exchange failed')
      end

      it 'raises an error' do
        expect { service.perform }.to raise_error(/Token exchange failed/)
      end

      it 'logs the error' do
        expect(Rails.logger).to receive(:tagged).with('WHATSAPP').and_yield
        expect(Rails.logger).to receive(:error).with(a_string_matching(/Embedded signup failed/))

        expect { service.perform }.to raise_error
      end
    end

    context 'when WABA info fetch fails' do
      let(:debug_token_response) do
        instance_double(Faraday::Response, success?: false, body: 'Debug token failed')
      end

      it 'raises an error' do
        expect { service.perform }.to raise_error(/WABA info fetch failed/)
      end
    end

    context 'when no WABA scope found' do
      let(:debug_token_response) do
        instance_double(
          Faraday::Response,
          success?: true,
          body: {
            data: {
              granular_scopes: [
                { scope: 'other_scope', target_ids: ['123'] }
              ]
            }
          }.to_json
        )
      end

      it 'raises an error' do
        expect { service.perform }.to raise_error(/No WABA scope found in token/)
      end
    end

    context 'when phone numbers fetch fails' do
      let(:phone_numbers_response) do
        instance_double(Faraday::Response, success?: false, body: 'Phone fetch failed')
      end

      it 'raises an error' do
        expect { service.perform }.to raise_error(/Phone info fetch failed/)
      end
    end

    context 'when no phone numbers found' do
      let(:phone_numbers_response) do
        instance_double(Faraday::Response, success?: true, body: { data: [] }.to_json)
      end

      it 'raises an error' do
        expect { service.perform }.to raise_error(/No phone numbers found for WABA/)
      end
    end

    context 'with unverified phone number' do
      let(:phone_numbers_response) do
        instance_double(
          Faraday::Response,
          success?: true,
          body: {
            data: [
              {
                id: phone_number_id,
                display_phone_number: phone_number,
                code_verification_status: 'UNVERIFIED'
              }
            ]
          }.to_json
        )
      end

      it 'still creates the channel with unverified phone' do
        channel = service.perform
        expect(channel.phone_number).to eq(phone_number)
        expect(channel.provider_config['phone_number_id']).to eq(phone_number_id)
      end
    end

    context 'when webhook setup fails' do
      let(:webhook_setup_response) do
        instance_double(Faraday::Response, success?: false, body: 'Webhook setup failed')
      end

      it 'continues and creates the channel anyway' do
        expect(Rails.logger).to receive(:tagged).with('WHATSAPP').and_yield
        expect(Rails.logger).to receive(:warn).with(a_string_matching(/Webhook setup failed but continuing/))

        expect { service.perform }.to change(Channel::Whatsapp, :count).by(1)
      end
    end
  end

  describe 'private methods' do
    describe '#encrypt_token' do
      it 'returns the token as-is for now' do
        expect(service.send(:encrypt_token, 'test_token')).to eq('test_token')
      end
    end

    describe '#webhooks_whatsapp_url' do
      it 'generates the correct webhook URL' do
        expected_url = Rails.application.routes.url_helpers.process_payload_webhooks_whatsapp_url(
          protocol: 'https',
          host: 'test.example.com'
        )
        
        expect(service.send(:webhooks_whatsapp_url, protocol: 'https', host: 'test.example.com'))
          .to eq(expected_url)
      end
    end
  end
end