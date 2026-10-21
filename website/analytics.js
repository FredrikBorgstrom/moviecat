// Google Analytics 4 (property "MovieCat (moviecat.org)"), loaded only after
// the visitor accepts. The choice is kept in localStorage; "Cookie settings"
// in the footer (any element with data-cookie-settings) asks again.
(function () {
  var ID = 'G-D964EWBB15', KEY = 'moviecat-analytics';
  var loaded = false;

  function getChoice() {
    try { return localStorage.getItem(KEY); } catch (e) { return null; }
  }
  function setChoice(v) {
    try { localStorage.setItem(KEY, v); } catch (e) {}
  }

  window.dataLayer = window.dataLayer || [];
  function gtag() { dataLayer.push(arguments); }
  window.gtag = gtag;

  function load() {
    if (loaded) return;
    loaded = true;
    gtag('consent', 'default', {
      analytics_storage: 'granted',
      ad_storage: 'denied', ad_user_data: 'denied', ad_personalization: 'denied'
    });
    gtag('js', new Date());
    gtag('config', ID, { allow_google_signals: false, allow_ad_personalization_signals: false });
    var s = document.createElement('script');
    s.async = true;
    s.src = 'https://www.googletagmanager.com/gtag/js?id=' + ID;
    document.head.appendChild(s);
  }

  // Events worth counting: downloads per platform and clicks on the ABCx3 promotion.
  document.addEventListener('click', function (e) {
    if (!loaded) return;
    var a = e.target.closest && e.target.closest('a');
    if (!a) return;
    if (a.matches('.dl, #hero-download') && /github\.com/.test(a.href)) {
      var mine = document.querySelector('.dl.mine');
      var os = a.dataset.os || (mine && mine.dataset.os) || 'unknown';
      gtag('event', 'moviecat_download', { platform: os, link_location: a.id ? 'hero' : 'download_section' });
    } else if (/play\.abcx3\.com|apps\.apple\.com\/.*abcx3/.test(a.href)) {
      var where = a.closest('header') ? 'header' : 'section';
      gtag('event', 'abcx3_click', { link_location: where, page_path: location.pathname });
    }
  });

  function banner() {
    if (document.getElementById('consent')) return;
    var box = document.createElement('div');
    box.id = 'consent';
    box.setAttribute('role', 'dialog');
    box.setAttribute('aria-label', 'Analytics cookies');
    box.innerHTML =
      '<p>May we use Google Analytics cookies to count visits? It helps us see what people are interested in. ' +
      '<a href="/privacy#website">Details</a></p>' +
      '<div class="consent-buttons"><button type="button" data-v="denied">No thanks</button>' +
      '<button type="button" class="yes" data-v="granted">Accept</button></div>';
    box.addEventListener('click', function (e) {
      var v = e.target.getAttribute && e.target.getAttribute('data-v');
      if (!v) return;
      var before = getChoice();
      setChoice(v);
      box.remove();
      if (v === 'granted') load();
      // Withdrawing consent: reload so the tag is no longer on the page.
      else if (before === 'granted') location.reload();
    });
    document.body.appendChild(box);
  }

  document.addEventListener('click', function (e) {
    if (e.target.closest && e.target.closest('[data-cookie-settings]')) {
      e.preventDefault();
      banner();
    }
  });

  var choice = getChoice();
  if (choice === 'granted') load();
  else if (choice !== 'denied') {
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', banner);
    else banner();
  }
})();
