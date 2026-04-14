/* Lightify — Spotify Web Playback SDK bridge (loaded in WKWebView) */
(function () {
  'use strict';

  var player = null;
  var pendingTokenCallback = null;

  function post(message) {
    try {
      window.webkit.messageHandlers.lightifySpotify.postMessage(JSON.stringify(message));
    } catch (e) {
      console.error('lightify post failed', e);
    }
  }

  function attachPlayerListeners() {
    if (!player) {
      return;
    }
    player.addListener('ready', function (ev) {
      post({ type: 'ready', device_id: ev.device_id });
    });
    player.addListener('not_ready', function (ev) {
      post({ type: 'not_ready', device_id: ev.device_id });
    });
    player.addListener('player_state_changed', function (state) {
      post({ type: 'player_state_changed', state: state });
    });
    player.addListener('autoplay_failed', function () {
      post({ type: 'autoplay_failed' });
    });
    player.addListener('initialization_error', function (e) {
      post({ type: 'initialization_error', message: e.message });
    });
    player.addListener('authentication_error', function (e) {
      post({ type: 'authentication_error', message: e.message });
    });
    player.addListener('account_error', function (e) {
      post({ type: 'account_error', message: e.message });
    });
    player.addListener('playback_error', function (e) {
      post({ type: 'playback_error', message: e.message });
    });
  }

  window.lightifyStartPlayer = function () {
    if (typeof Spotify === 'undefined') {
      post({ type: 'initialization_error', message: 'Spotify global not loaded' });
      return;
    }
    if (player) {
      post({ type: 'log', message: 'Player already exists' });
      return;
    }
    player = new Spotify.Player({
      name: 'Lightify',
      getOAuthToken: function (cb) {
        pendingTokenCallback = cb;
        post({ type: 'need_token' });
      },
      volume: 0.85
    });
    attachPlayerListeners();
    player.connect().then(function (ok) {
      post({ type: 'connect_result', success: !!ok });
    });
  };

  window.lightifyDeliverToken = function (token) {
    if (pendingTokenCallback) {
      var cb = pendingTokenCallback;
      pendingTokenCallback = null;
      cb(token);
    }
  };

  window.lightifyTogglePlay = function () {
    if (!player) {
      return;
    }
    player.togglePlay();
  };

  window.lightifyPlay = function () {
    if (!player) {
      return;
    }
    player.resume().catch(function (e) {
      post({ type: 'log', message: 'resume failed: ' + (e && e.message ? e.message : String(e)) });
    });
  };

  window.lightifyPause = function () {
    if (!player) {
      return;
    }
    player.pause().catch(function (e) {
      post({ type: 'log', message: 'pause failed: ' + (e && e.message ? e.message : String(e)) });
    });
  };

  window.lightifyNext = function () {
    if (!player) {
      return;
    }
    player.nextTrack();
  };

  window.lightifyPrevious = function () {
    if (!player) {
      return;
    }
    player.previousTrack();
  };

  window.lightifyActivateElement = function () {
    if (!player) {
      return;
    }
    player.activateElement();
  };

  window.lightifyDisconnect = function () {
    if (!player) {
      return;
    }
    player.disconnect();
    player = null;
  };

  window.lightifySetVolume = function (v) {
    if (!player) {
      return;
    }
    var x = Number(v);
    if (isNaN(x)) {
      return;
    }
    if (x < 0) {
      x = 0;
    } else if (x > 1) {
      x = 1;
    }
    player.setVolume(x).catch(function (e) {
      post({ type: 'log', message: 'setVolume failed: ' + (e && e.message ? e.message : String(e)) });
    });
  };

  window.lightifySeek = function (ms) {
    if (!player) {
      return;
    }
    var x = Number(ms);
    if (isNaN(x)) {
      return;
    }
    if (x < 0) {
      x = 0;
    }
    player.seek(x).catch(function (e) {
      post({ type: 'log', message: 'seek failed: ' + (e && e.message ? e.message : String(e)) });
    });
  };

  window.onSpotifyWebPlaybackSDKReady = function () {
    post({ type: 'sdk_ready' });
  };
})();
