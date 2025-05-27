<script>
export default {
  data() {
    return {
      fbSdkLoaded: false,
    };
  },
  mounted() {
    this.loadFacebookSdk();
    window.addEventListener('message', this.handleSignupMessage);
  },
  beforeDestroy() {
    window.removeEventListener('message', this.handleSignupMessage);
  },
  methods: {
    loadFacebookSdk() {
      if (window.FB) {
        this.fbSdkLoaded = true;
        return;
      }
      const script = document.createElement('script');
      script.src = 'https://connect.facebook.net/en_US/sdk.js';
      script.async = true;
      script.defer = true;
      console.log('loading facebook sdk');
      console.log('window.chatwootConfig.fbAppId', window.chatwootConfig.fbAppId);
      script.onload = () => {
        window.FB.init({
          appId: window.chatwootConfig.fbAppId, // from config
          autoLogAppEvents: true,
          xfbml: true,
          version: window.chatwootConfig.fbApiVersion || 'v22.0',
        });
        this.fbSdkLoaded = true;
      };
      document.body.appendChild(script);
    },
    launchEmbeddedSignup() {
      if (!window.FB) {
        this.loadFacebookSdk();
        return;
      }
      window.FB.login(this.fbLoginCallback, {
        config_id: window.chatwootConfig.whatsappConfigurationId, // your config id
        response_type: 'code',
        override_default_response_type: true,
        extras: {
          setup: {},
          featureType: '',
          sessionInfoVersion: '3',
        },
      });
    },
    fbLoginCallback(response) {
      console.log('fbLoginCallback', response);
      if (response.authResponse) {
        const code = response.authResponse.code;
        // Send code to backend or handle as needed
        console.log('Embedded Signup code:', code);
      } else {
        console.log('Embedded Signup response:', response);
      }
    },
    handleSignupMessage(event) {
      if (!event.origin.endsWith('facebook.com')) return;
      try {
        const data = JSON.parse(event.data);
        if (data.type === 'WA_EMBEDDED_SIGNUP') {
          console.log('Embedded Signup message event:', data);
          // Handle signup result (success, cancel, error)
        }
      } catch {
        console.log('Embedded Signup message event:', event.data);
      }
    },
  },
};
</script>

<template>
  <div>
    <button @click="launchEmbeddedSignup">
      Start WhatsApp Embedded Signup
    </button>
  </div>
</template>
