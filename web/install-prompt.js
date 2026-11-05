/* Home-screen installation is progressive: browsers keep control of native prompts. */
(function () {
  'use strict';
  if (window.__domlyInstallPrompt) return;
  window.__domlyInstallPrompt = true;

  var standalone = window.matchMedia('(display-mode: standalone)');
  var ua = navigator.userAgent;
  var ios = /iPad|iPhone|iPod/.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  var android = /Android/.test(ua);
  var embedded = /FBAN|FBAV|Instagram|Line\/|; wv\)|Telegram/i.test(ua);
  var safari = ios && /Safari/.test(ua) && !/CriOS|FxiOS|EdgiOS|OPiOS/.test(ua);
  var key = 'domly-install-dismissed:' + new URL('.', document.baseURI).pathname;
  var deferredPrompt = null;
  var dialog, installButton, instructions, previouslyFocused;
  var installed = false;
  function isStandalone() {
    return installed || standalone.matches || navigator.standalone === true || document.referrer.indexOf('android-app://') === 0;
  }
  function dismissed() {
    try { return sessionStorage.getItem(key) === '1'; } catch (_) { return false; }
  }
  function close() {
    try { sessionStorage.setItem(key, '1'); } catch (_) {}
    if (dialog && dialog.open) dialog.close();
    if (previouslyFocused && previouslyFocused.isConnected) previouslyFocused.focus();
  }
  function update() {
    if (!dialog) return;
    installButton.hidden = !deferredPrompt || ios || embedded;
    if (ios) {
      instructions.textContent = safari
        ? 'Нажмите «Поделиться» (значок со стрелкой вверх) в Safari → «На экран „Домой“» → «Добавить».'
        : 'Откройте эту ссылку в Safari. Затем нажмите «Поделиться» → «На экран „Домой“» → «Добавить».';
    } else if (embedded) {
      instructions.textContent = 'Откройте ссылку в Chrome через меню этого окна. Затем выберите «Установить приложение» или «Добавить на главный экран».';
    } else if (deferredPrompt) {
      instructions.textContent = 'Нажмите «Установить», затем подтвердите установку в окне браузера.';
    } else if (android) {
      instructions.textContent = 'В Chrome нажмите меню ⋮ → «Добавить на главный экран» или «Установить приложение». Затем подтвердите добавление.';
    } else {
      instructions.textContent = 'В меню браузера выберите «Установить приложение» или «Добавить на главный экран». Если такого пункта нет, откройте ссылку в Chrome или Edge.';
    }
  }
  function show() {
    if (isStandalone() || dismissed() || !window.HTMLDialogElement) return;
    if (!dialog) {
      var style = document.createElement('style');
      style.textContent = '#domly-install{box-sizing:border-box;width:calc(100% - 32px);max-width:420px;max-height:calc(100dvh - 32px);overflow:auto;margin:auto;border:1px solid #deece3;border-radius:24px;padding:26px;background:#f6fbf7;color:#20382f;font:16px/1.5 system-ui,-apple-system,sans-serif;box-shadow:0 20px 80px #0004}#domly-install::backdrop{background:#10291fc0}#domly-install h2{font-size:23px;line-height:1.25;margin:14px 0 10px}#domly-install p{margin:10px 0}#domly-install .domly-install-icon{width:64px;height:64px;border-radius:16px}#domly-install .domly-install-steps{background:white;border:1px solid #deece3;border-radius:14px;padding:14px;margin:18px 0;color:#395847}#domly-install .domly-install-actions{display:flex;flex-wrap:wrap;gap:10px;margin-top:20px}#domly-install button{flex:1;min-width:130px;min-height:48px;padding:12px 18px;border-radius:14px;border:1px solid #abcbb8;background:transparent;color:#20382f;font:600 16px system-ui;cursor:pointer}#domly-install button[data-install]{background:#c66e43;border-color:#c66e43;color:white}#domly-install button:focus-visible{outline:3px solid #439f73;outline-offset:3px}#domly-install button[hidden]{display:none}#domly-install button:disabled{opacity:.6;cursor:wait}';
      document.head.appendChild(style);
      dialog = document.createElement('dialog');
      dialog.id = 'domly-install';
      dialog.setAttribute('aria-labelledby', 'domly-install-title');
      dialog.setAttribute('aria-describedby', 'domly-install-description domly-install-steps');
      // All markup is static; no URL parameters or customer data are interpolated.
      dialog.innerHTML = '<img class="domly-install-icon" src="icons/Icon-192.png" alt="" width="64" height="64"><h2 id="domly-install-title">DomLY на главном экране</h2><p id="domly-install-description">Добавьте значок DomLY и открывайте сервис одним нажатием — без поиска ссылки в браузере.</p><p class="domly-install-steps" id="domly-install-steps"></p><div class="domly-install-actions"><button type="button" data-install hidden>Установить</button><button type="button" data-close>Позже</button></div>';
      document.body.appendChild(dialog);
      installButton = dialog.querySelector('[data-install]');
      instructions = dialog.querySelector('#domly-install-steps');
      dialog.querySelector('[data-close]').addEventListener('click', close);
      dialog.addEventListener('cancel', function (event) { event.preventDefault(); close(); });
      dialog.addEventListener('click', function (event) { if (event.target === dialog) {
        var bounds = dialog.getBoundingClientRect();
        if (event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom) close();
      } });
      installButton.addEventListener('click', async function () {
        var prompt = deferredPrompt;
        if (!prompt) return;
        deferredPrompt = null;
        installButton.disabled = true;
        try {
          await prompt.prompt();
          var choice = await prompt.userChoice;
          if (choice.outcome === 'accepted') { close(); return; }
        } catch (_) { /* Keep manual instructions available if the browser refuses. */ }
        finally { installButton.disabled = false; update(); }
      });
    }
    update();
    if (!dialog.open) {
      previouslyFocused = document.activeElement;
      dialog.showModal();
    }
  }
  window.addEventListener('beforeinstallprompt', function (event) {
    event.preventDefault();
    deferredPrompt = event;
    update();
    // Do not reopen a dismissed dialog if Chrome announces installability late.
  });
  window.addEventListener('appinstalled', function () { installed = true; deferredPrompt = null; close(); });
  function standaloneChanged() { if (isStandalone()) close(); }
  if (standalone.addEventListener) standalone.addEventListener('change', standaloneChanged);
  window.addEventListener('pageshow', standaloneChanged);
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () { window.setTimeout(show, 1600); }, {once:true});
  } else {
    window.setTimeout(show, 1600);
  }
})();
