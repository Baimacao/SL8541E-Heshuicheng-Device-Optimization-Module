/* ═══════════════════════════════════════
 * 优化模块 WebUI 脚本
 * 兼容 WebView 80（Chrome 80）
 * 只负责 Tab 切换，状态由 iframe 静态加载
 * ═══════════════════════════════════════ */

(function () {
    'use strict';

    function switchTab(name) {
        var btns = document.querySelectorAll('.tab-btn');
        for (var i = 0; i < btns.length; i++) {
            if (btns[i].getAttribute('data-tab') === name) {
                btns[i].classList.add('active');
            } else {
                btns[i].classList.remove('active');
            }
        }
        var panels = document.querySelectorAll('.tab-panel');
        for (var j = 0; j < panels.length; j++) {
            if (panels[j].id === 'tab-' + name) {
                panels[j].classList.add('active');
            } else {
                panels[j].classList.remove('active');
            }
        }
        window.scrollTo(0, 0);
    }

    document.addEventListener('DOMContentLoaded', function () {
        var btns = document.querySelectorAll('.tab-btn');
        for (var i = 0; i < btns.length; i++) {
            (function (btn) {
                btn.addEventListener('click', function () {
                    switchTab(btn.getAttribute('data-tab'));
                });
            })(btns[i]);
        }
    });
})();