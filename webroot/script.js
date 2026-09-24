/* ═══════════════════════════════════════════════════════════
 * 优化模块 WebUI 脚本
 * 兼容 WebView 80（Chrome 80）—— 所以用 var / 普通函数，
 * 不用 let/const、不用箭头函数、不用可选链。
 *
 * 只干两件事：
 *   1. Tab 切换（不依赖任何框架）
 *   2. 点回「状态」Tab 时给 iframe 加时间戳，强制重载
 *      —— 状态页是开机时生成的静态文件，不加时间戳浏览器会吃缓存
 * ═══════════════════════════════════════════════════════════ */

(function () {
    'use strict';

    function switchTab(name) {
        var i;
        var btns = document.querySelectorAll('.tab-btn');
        for (i = 0; i < btns.length; i++) {
            if (btns[i].getAttribute('data-tab') === name) {
                btns[i].classList.add('active');
            } else {
                btns[i].classList.remove('active');
            }
        }

        var panels = document.querySelectorAll('.tab-panel');
        for (i = 0; i < panels.length; i++) {
            if (panels[i].id === 'tab-' + name) {
                panels[i].classList.add('active');
            } else {
                panels[i].classList.remove('active');
            }
        }

        // 回到状态页时刷新 iframe：状态是静态快照，缓存住就永远看的是旧的
        if (name === 'status') {
            var frame = document.getElementById('status-frame');
            if (frame) {
                frame.setAttribute('src', 'status_generated.html?t=' + (new Date()).getTime());
            }
        }

        window.scrollTo(0, 0);
    }

    function bindTabs() {
        var btns = document.querySelectorAll('.tab-btn');
        for (var i = 0; i < btns.length; i++) {
            (function (btn) {
                btn.addEventListener('click', function () {
                    switchTab(btn.getAttribute('data-tab'));
                });
            })(btns[i]);
        }

        // 版本号写死在页面里，省一次请求（模块版本在 module.prop 里改了，
        // 这里也要跟着改，或者干脆点「操作」按钮看报告里的真实版本）
        var ver = document.getElementById('version');
        if (ver) { ver.textContent = 'v1.5'; }
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', bindTabs);
    } else {
        bindTabs();
    }
})();
