// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:js' as js;

Timer? _timer;

void primeOfferAlertSound() {
  js.context.callMethod('eval', [
    r'''
(() => {
  try {
    window.__domlyOfferAudioUnlocked = true;
    if (window.__domlyOfferAudioPrimed) return;
    const AudioContext = window.AudioContext || window.webkitAudioContext;
    if (!AudioContext) return;
    const ctx = window.__domlyOfferAudioCtx || new AudioContext();
    window.__domlyOfferAudioCtx = ctx;
    if (ctx.state === 'suspended') {
      ctx.resume && ctx.resume();
    }
    const gain = ctx.createGain();
    const osc = ctx.createOscillator();
    gain.gain.setValueAtTime(0.0001, ctx.currentTime);
    osc.frequency.setValueAtTime(1, ctx.currentTime);
    osc.connect(gain);
    gain.connect(ctx.destination);
    osc.start();
    osc.stop(ctx.currentTime + 0.01);
    window.__domlyOfferAudioPrimed = true;
    if (window.__domlyOfferAlertActive && window.__domlyOfferPlayBeep) {
      window.__domlyOfferPlayBeep();
    }
  } catch (_) {}
})()
''',
  ]);
}

void startOfferAlertSound({
  bool enabled = true,
  double volume = 1,
  int soundIndex = 0,
}) {
  if (!enabled) {
    stopOfferAlertSound();
    return;
  }
  final safeVolume = volume.clamp(0.0, 1.0).toStringAsFixed(2);
  final safeSoundIndex = soundIndex.clamp(0, 20);
  js.context.callMethod('eval', [
    'window.__domlyOfferAlertActive = true;'
        'window.__domlyOfferAlertVolume = $safeVolume;'
        'window.__domlyOfferAlertSoundIndex = $safeSoundIndex;'
  ]);
  if (_timer != null) {
    return;
  }
  _playBeep();
  _timer = Timer.periodic(const Duration(seconds: 2), (_) => _playBeep());
}

void stopOfferAlertSound() {
  js.context.callMethod('eval', ['window.__domlyOfferAlertActive = false;']);
  _timer?.cancel();
  _timer = null;
}

void _playBeep() {
  js.context.callMethod('eval', [
    r'''
(() => {
  try {
    window.__domlyOfferAlertActive = true;
    const AudioContext = window.AudioContext || window.webkitAudioContext;
    if (!AudioContext) return;
    const ctx = window.__domlyOfferAudioCtx || new AudioContext();
    window.__domlyOfferAudioCtx = ctx;
    if (ctx.state === 'suspended') {
      ctx.resume && ctx.resume();
    }
    const play = () => {
      try {
        const variants = [
          [[980, 980, 0.35, 'sine', 0], [1320, 1320, 0.35, 'sine', 0.46]],
          [[523, 784, 0.55, 'sine', 0], [659, 1046, 0.55, 'sine', 0.7]],
          [[880, 880, 0.16, 'sine', 0], [880, 880, 0.16, 'sine', 0.24], [880, 880, 0.16, 'sine', 0.48]],
          [[440, 660, 0.34, 'triangle', 0], [392, 587, 0.44, 'triangle', 0.48]],
          [[500, 1400, 0.9, 'sine', 0], [1400, 600, 0.65, 'sine', 1.05]],
          [[1800, 1800, 0.07, 'square', 0], [1800, 1800, 0.07, 'square', 0.12], [1800, 1800, 0.07, 'square', 0.24], [1800, 1800, 0.07, 'square', 0.36]],
          [[650, 650, 0.12, 'square', 0], [980, 980, 0.12, 'square', 0.2], [650, 650, 0.12, 'square', 0.62], [980, 980, 0.12, 'square', 0.82]],
          [[350, 1600, 0.55, 'sawtooth', 0], [1600, 350, 0.55, 'sawtooth', 0.55]],
          [[740, 988, 0.15, 'square', 0], [740, 988, 0.15, 'square', 0.31], [740, 988, 0.15, 'square', 0.62], [740, 988, 0.15, 'square', 0.93]],
          [[1200, 1200, 0.5, 'square', 0], [1200, 1200, 0.5, 'square', 0.62]],
          [[330, 330, 0.25, 'triangle', 0], [660, 660, 0.25, 'triangle', 0.3], [330, 330, 0.25, 'triangle', 0.62], [660, 660, 0.25, 'triangle', 0.92]],
          [[900, 1300, 0.11, 'sine', 0], [900, 1300, 0.11, 'sine', 0.22], [900, 1300, 0.11, 'sine', 0.44], [900, 1300, 0.11, 'sine', 0.66], [900, 1300, 0.11, 'sine', 0.88]],
          [[880, 1320, 1.15, 'sine', 0]],
          [[2400, 2400, 0.05, 'square', 0], [2400, 2400, 0.05, 'square', 0.1], [2400, 2400, 0.05, 'square', 0.2], [2400, 2400, 0.05, 'square', 0.3], [2400, 2400, 0.05, 'square', 0.4]],
          [[220, 900, 1.35, 'sawtooth', 0], [1200, 1200, 0.25, 'square', 1.5]],
          [[392, 659, 0.22, 'sine', 0], [392, 659, 0.22, 'sine', 0.4], [392, 659, 0.22, 'sine', 0.8]],
          [[1500, 1500, 0.2, 'square', 0], [600, 600, 0.2, 'square', 0.3], [1500, 1500, 0.42, 'square', 0.6]],
          [[700, 2100, 0.25, 'square', 0], [700, 2100, 0.25, 'square', 0.3], [700, 2100, 0.25, 'square', 0.6], [700, 2100, 0.25, 'square', 0.9]],
          [[262, 587, 0.85, 'triangle', 0], [392, 784, 0.85, 'triangle', 1.0]],
          [[1000, 1000, 0.07, 'sine', 0], [1600, 1600, 0.07, 'sine', 0.14], [1000, 1000, 0.07, 'sine', 0.43], [1600, 1600, 0.07, 'sine', 0.5]],
          [[450, 1900, 1.0, 'sawtooth', 0], [95, 95, 1.0, 'square', 0], [1900, 450, 1.0, 'sawtooth', 1.1], [120, 120, 1.0, 'square', 1.1]],
        ];
        const variant = variants[Math.max(0, Math.min(20, window.__domlyOfferAlertSoundIndex || 0))];
        const volume = Math.max(0, Math.min(1, window.__domlyOfferAlertVolume ?? 1));
        variant.forEach((step) => {
          const gain = ctx.createGain();
          const osc = ctx.createOscillator();
          const startAt = ctx.currentTime + step[4];
          const endAt = startAt + step[2];
          gain.gain.setValueAtTime(0.0001, startAt);
          gain.gain.exponentialRampToValueAtTime(Math.max(0.01, volume), startAt + 0.025);
          gain.gain.exponentialRampToValueAtTime(0.0001, endAt);
          osc.type = step[3];
          osc.frequency.setValueAtTime(step[0], startAt);
          osc.frequency.linearRampToValueAtTime(step[1], endAt);
          osc.connect(gain);
          gain.connect(ctx.destination);
          osc.start(startAt);
          osc.stop(endAt + 0.02);
        });
      } catch (_) {}
    };
    window.__domlyOfferPlayBeep = play;
    if (ctx.state === 'suspended' && !window.__domlyOfferAudioUnlocked) {
      return;
    }
    play();
  } catch (_) {}
})()
''',
  ]);
}
