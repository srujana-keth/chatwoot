require 'rails_helper'

RSpec.describe 'WhatsApp Embedded Signup', type: :system do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }

  before do
    sign_in user
    
    # Mock Facebook SDK availability
    page.execute_script(<<~JS)
      window.chatwootConfig = {
        fbAppId: 'test_app_id_123',
        fbApiVersion: 'v21.0',
        whatsappConfigId: 'test_config_id_456'
      };
      
      window.FB = {
        init: function() {},
        AppEvents: { logPageView: function() {} },
        login: function(callback, options) {
          callback({
            authResponse: { code: 'test_auth_code_123' }
          });
        }
      };
      
      window.fbSDKLoaded = true;
    JS
  end

  context 'when creating a new WhatsApp inbox' do
    before do
      # Mock the backend API responses
      stub_request(:get, '/whatsapp/callback')
        .with(query: { code: 'test_auth_code_123' })
        .to_return(
          status: 200,
          body: { status: 'processing', job_id: 'job_123' }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'shows WhatsApp Embedded Signup option in provider list' do
      visit '/app/accounts/1/settings/inboxes/new'
      click_on 'WhatsApp'

      expect(page).to have_select('API Provider', with_options: ['WhatsApp Business (Embedded Signup)'])
      expect(page).to have_css('option[value="whatsapp_embedded"]')
    end

    it 'displays embedded signup form when selected' do
      visit '/app/accounts/1/settings/inboxes/new/whatsapp'
      
      select 'WhatsApp Business (Embedded Signup)', from: 'API Provider'

      expect(page).to have_text('Quick Setup with Meta')
      expect(page).to have_text('Connect your WhatsApp Business Account')
      expect(page).to have_text('Benefits of Embedded Signup:')
      expect(page).to have_text('One-click setup with no manual configuration')
      expect(page).to have_button('Connect with WhatsApp Business')
    end

    it 'initiates signup flow when button is clicked' do
      visit '/app/accounts/1/settings/inboxes/new/whatsapp'
      
      select 'WhatsApp Business (Embedded Signup)', from: 'API Provider'
      click_button 'Connect with WhatsApp Business'

      expect(page).to have_text('Setting up your WhatsApp Business Account...')
    end

    context 'with successful signup flow' do
      before do
        # Mock ActionCable to simulate real-time updates
        page.execute_script(<<~JS)
          window.App = {
            cable: {
              subscriptions: {
                create: function(channel, callbacks) {
                  setTimeout(function() {
                    callbacks.received({
                      type: 'whatsapp_signup_completed',
                      data: { 
                        channel_id: 1, 
                        inbox_id: 1, 
                        status: 'success' 
                      }
                    });
                  }, 1000);
                  return { unsubscribe: function() {} };
                }
              }
            }
          };
        JS
      end

      it 'shows success message and redirects on completion', js: true do
        visit '/app/accounts/1/settings/inboxes/new/whatsapp'
        
        select 'WhatsApp Business (Embedded Signup)', from: 'API Provider'
        click_button 'Connect with WhatsApp Business'

        expect(page).to have_text('Setting up your WhatsApp Business Account...')
        
        # Wait for ActionCable message simulation
        sleep 1.5
        
        expect(page).to have_text('WhatsApp channel created successfully!')
      end
    end

    context 'with failed signup flow' do
      before do
        page.execute_script(<<~JS)
          window.App = {
            cable: {
              subscriptions: {
                create: function(channel, callbacks) {
                  setTimeout(function() {
                    callbacks.received({
                      type: 'whatsapp_signup_failed',
                      data: { 
                        error: 'Failed to connect to WhatsApp Business API',
                        status: 'failed' 
                      }
                    });
                  }, 1000);
                  return { unsubscribe: function() {} };
                }
              }
            }
          };
        JS
      end

      it 'shows error message on failure', js: true do
        visit '/app/accounts/1/settings/inboxes/new/whatsapp'
        
        select 'WhatsApp Business (Embedded Signup)', from: 'API Provider'
        click_button 'Connect with WhatsApp Business'

        expect(page).to have_text('Setting up your WhatsApp Business Account...')
        
        # Wait for ActionCable message simulation
        sleep 1.5
        
        expect(page).to have_text('Failed to connect to WhatsApp Business API')
      end
    end
  end

  context 'when Facebook SDK fails to load' do
    before do
      page.execute_script('window.FB = undefined; window.fbSDKLoaded = false;')
    end

    it 'shows error when SDK is not available' do
      visit '/app/accounts/1/settings/inboxes/new/whatsapp'
      
      select 'WhatsApp Business (Embedded Signup)', from: 'API Provider'
      click_button 'Connect with WhatsApp Business'

      expect(page).to have_text('Facebook SDK not ready. Please try again.')
    end
  end
end