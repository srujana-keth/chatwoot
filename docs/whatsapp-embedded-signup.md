# WhatsApp Business Embedded Signup

This feature allows users to connect their WhatsApp Business Account to Chatwoot using Meta's Embedded Signup flow, providing a seamless one-click setup experience.

## Overview

The WhatsApp Business Embedded Signup (WBES) feature integrates with Meta's OAuth flow to automatically:
- Exchange authorization codes for access tokens
- Retrieve WhatsApp Business Account (WABA) information
- Fetch and configure phone numbers
- Set up webhook subscriptions
- Create the WhatsApp channel in Chatwoot

## Architecture

### Backend Components

- **Controller**: `Whatsapp::EmbeddedController` - Handles OAuth callback
- **Service**: `Whatsapp::EmbeddedSignupService` - Manages the signup process
- **Job**: `Whatsapp::EmbeddedSignupJob` - Background processing with retries
- **Routes**: `/whatsapp/signup` and `/whatsapp/callback`

### Frontend Components

- **Vue Component**: `WhatsappEmbeddedSignup.vue` - UI for embedded signup
- **Provider Option**: Added to existing WhatsApp channel selector

## Configuration

### Environment Variables

```bash
WHATSAPP_APP_ID=your_facebook_app_id
WHATSAPP_APP_SECRET=your_facebook_app_secret
WHATSAPP_CONFIG_ID=your_whatsapp_config_id (optional, defaults to APP_ID)
FRONTEND_URL=https://your-chatwoot-instance.com
```

### Facebook App Configuration

1. Create a Facebook App with WhatsApp Business API product
2. Configure WhatsApp Business Embedded Signup
3. Add your Chatwoot domain to allowed domains
4. Set webhook URL to: `https://your-domain.com/webhooks/whatsapp/:phone_number`

## API Flow

1. **Initiate Signup** - User clicks "Connect with WhatsApp Business"
2. **OAuth Flow** - Facebook SDK handles authentication
3. **Callback Processing** - Authorization code sent to `/whatsapp/callback`
4. **Background Job** - `EmbeddedSignupJob` processes the signup
5. **Token Exchange** - Trade auth code for access token
6. **WABA Discovery** - Find WhatsApp Business Account ID
7. **Phone Setup** - Configure phone numbers and webhooks
8. **Channel Creation** - Create/update WhatsApp channel
9. **Real-time Updates** - ActionCable broadcasts completion status

## Error Handling

The system handles various error scenarios:
- Invalid authorization codes
- Network failures during API calls
- Missing permissions or scopes
- Webhook configuration failures

All errors are logged with the `WHATSAPP` tag and user-friendly messages are displayed.

## Testing

### RSpec Tests
- Service layer tests with WebMock for API stubbing
- Controller tests for authorization and error handling
- Job tests for retry behavior and ActionCable broadcasting
- System tests with Selenium for E2E flow

### Manual Testing
1. Start the application with proper environment variables
2. Navigate to Settings → Inboxes → New Inbox → WhatsApp
3. Select "WhatsApp Business (Embedded Signup)"
4. Click "Connect with WhatsApp Business"
5. Complete Facebook OAuth flow
6. Verify channel creation and webhook setup

## Security Considerations

- Access tokens are stored securely (implement encryption in production)
- OAuth flow uses secure state parameters
- Webhook verification tokens are randomly generated
- All API calls use HTTPS with proper authentication headers

## Limitations

- Requires Facebook App with WhatsApp Business API access
- Limited to accounts with appropriate Meta Business verification
- Phone numbers must be verified in Meta Business Manager
- Webhook setup depends on proper DNS and SSL configuration