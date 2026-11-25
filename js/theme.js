/*
 * Light/dark theme. Loaded in <head> (not deferred) so the theme is set before the page is drawn.
 *
 * The choice is 'auto' (follow the operating system / browser), 'light' or 'dark'. It is kept per browser
 * in localStorage; 'auto' is the default and is not stored. The resolved theme ends up as
 * <html data-theme="light|dark">, which css/dark.css keys on; data-theme-pref holds the choice itself.
 * Any element with id "themetoggle" cycles auto -> light -> dark and shows the current choice.
 */
(function () {
    'use strict';

    var KEY = 'nsedit-theme';
    var ORDER = ['auto', 'light', 'dark'];
    var LABEL = {auto: 'Theme: auto', light: 'Theme: light', dark: 'Theme: dark'};
    var media = window.matchMedia ? window.matchMedia('(prefers-color-scheme: dark)') : null;
    var fallback = 'auto'; // used when localStorage is unavailable (private mode, blocked storage)

    function load() {
        try {
            var value = window.localStorage.getItem(KEY);
            return (value === 'light' || value === 'dark') ? value : 'auto';
        } catch (e) {
            return fallback;
        }
    }

    function save(value) {
        fallback = value;
        try {
            if (value === 'auto') {
                window.localStorage.removeItem(KEY);
            } else {
                window.localStorage.setItem(KEY, value);
            }
        } catch (e) {
            // not stored: the choice lasts until the page is reloaded
        }
    }

    function label() {
        var button = document.getElementById('themetoggle');
        if (button) {
            var pref = load();
            button.textContent = LABEL[pref];
            button.title = pref === 'auto'
                ? 'Follows the system setting (now ' + document.documentElement.getAttribute('data-theme') + '). Click to change.'
                : 'Click to change the theme.';
        }
    }

    function apply() {
        var pref = load();
        var dark = pref === 'dark' || (pref === 'auto' && media !== null && media.matches);
        document.documentElement.setAttribute('data-theme', dark ? 'dark' : 'light');
        document.documentElement.setAttribute('data-theme-pref', pref);
        label();
    }

    apply();

    if (media !== null) {
        if (media.addEventListener) {
            media.addEventListener('change', apply);
        } else if (media.addListener) {
            media.addListener(apply);
        }
    }

    // another tab changed the theme
    window.addEventListener('storage', function (event) {
        if (event.key === KEY || event.key === null) {
            apply();
        }
    });

    document.addEventListener('DOMContentLoaded', function () {
        var button = document.getElementById('themetoggle');
        if (!button) {
            return;
        }
        button.addEventListener('click', function (event) {
            event.preventDefault();
            save(ORDER[(ORDER.indexOf(load()) + 1) % ORDER.length]);
            apply();
        });
        label();
    });
}());
