// Refresh rate in ms
const REFRESH_RATE = 1000;
let chartInstance = null;
let currentTab = 'live';

async function updateDashboard() {
    if (currentTab !== 'live') return;

    try {
        const response = await fetch('/api/live');
        const data = await response.json();

        if (!data || Object.keys(data).length === 0) return;

        // 1. Update Header Info
        document.getElementById('cycle-count').innerText = data.id || '-';
        document.getElementById('clock').innerText = new Date().toLocaleTimeString();

        // 2. Risk Gauge
        const risk = Math.round((data.total_risk || 0) * 100);
        const gauge = document.getElementById('total-risk-gauge');
        const gaugeVal = document.getElementById('total-risk-val');

        gauge.style.setProperty('--percent', risk);
        gaugeVal.innerText = risk;

        // Color Coding
        let color = 'var(--risk-low)';
        if (risk > 30) color = 'var(--risk-med)';
        if (risk > 60) color = 'var(--risk-high)';
        if (risk > 80) color = 'var(--risk-crit)';

        gauge.style.background = `conic-gradient(${color} calc(var(--percent) * 1%), #334155 0)`;

        // Alert Banner
        const banner = document.getElementById('alert-banner');
        if (risk > 80) {
            banner.classList.remove('hidden');
        } else {
            banner.classList.add('hidden');
        }

        // 3. Breakdown Bars
        updateBar('vision', data.image_risk);
        updateBar('text', data.text_risk);
        updateBar('behavior', data.behavior_risk);

        // 4. Live Image
        const img = document.getElementById('live-screenshot');
        if (data.screenshot_url) {
            img.src = `${data.screenshot_url}?t=${Date.now()}`;
        }

        // 5. Text Log
        const log = document.getElementById('ocr-text-log');
        if (data.extracted_text) {
            const p = document.createElement('p');
            p.innerText = `[${new Date().toLocaleTimeString()}] ${data.extracted_text.substring(0, 100)}...`;
            p.style.borderBottom = "1px solid #333";
            p.style.marginBottom = "5px";
            log.prepend(p);
            if (log.children.length > 20) log.lastChild.remove();
        }

    } catch (e) {
        console.error("Dashboard update failed:", e);
    }
}

function updateBar(id, val) {
    const pct = Math.round((val || 0) * 100);
    document.getElementById(`${id}-bar`).style.width = `${pct}%`;
    document.getElementById(`${id}-val`).innerText = `${pct}%`;
}

function switchTab(tab) {
    currentTab = tab;
    // Hide all
    currentTab = tab;
    // Hide all main containers
    document.querySelectorAll('.dashboard-grid > div').forEach(el => {
        // We only want to hide top-level cards, but our structure is nested.
        // Simpler: Hide specific IDs
        el.classList.add('hidden');
    });

    // Reset visibility logic
    const liveCards = document.querySelectorAll('.screen-view-card, .risk-card, .text-card, .chart-card');
    const analysisView = document.getElementById('analysis-view');
    const historyView = document.getElementById('history-view');

    liveCards.forEach(c => c.classList.add('hidden'));
    analysisView.classList.add('hidden');
    historyView.classList.add('hidden');

    // Update active button state
    document.querySelectorAll('nav button').forEach(b => b.classList.remove('active'));
    // (This simple logic assumes buttons are in order: Live, Analysis, History)
    const btns = document.querySelectorAll('nav button');
    if (tab === 'live') btns[0].classList.add('active');
    if (tab === 'analysis') btns[1].classList.add('active');
    if (tab === 'history') btns[2].classList.add('active');

    // Show selected
    if (tab === 'live') {
        liveCards.forEach(c => c.classList.remove('hidden'));
        document.getElementById('page-title').innerText = "Live Monitoring";
    } else if (tab === 'analysis') {
        analysisView.classList.remove('hidden');
        document.getElementById('page-title').innerText = "Behavioral Analytics";
        loadAnalytics();
    } else if (tab === 'history') {
        historyView.classList.remove('hidden');
        document.getElementById('page-title').innerText = "History Log";
        loadHistory();
    }
}

async function loadHistory() {
    try {
        const res = await fetch('/api/history'); // Returns last 20
        const hist = await res.json();
        const container = document.getElementById('history-container');
        container.innerHTML = ''; // Clear

        hist.forEach(item => {
            const risk = Math.round((item.total_risk || 0) * 100);
            let color = '#22c55e'; // Green
            if (risk > 30) color = '#eab308';
            if (risk > 60) color = '#f97316';
            if (risk > 80) color = '#ef4444';

            const div = document.createElement('div');
            div.className = 'history-item';

            // Thumbnail
            let imgUrl = item.screenshot_url ? item.screenshot_url : 'https://via.placeholder.com/150x100?text=No+Img';

            const timeStr = new Date(item.timestamp * 1000).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });

            div.innerHTML = `
                <img src="${imgUrl}" class="history-thumb" loading="lazy">
                <div class="history-meta">
                    <div style="display:flex; justify-content:space-between; margin-bottom:5px;">
                        <span>${timeStr}</span>
                        <span class="risk-badge" style="background:${color}">${risk}</span>
                    </div>
                     <div style="font-size:0.7em; color:#94a3b8;">${item.app_name || 'Unknown'}</div>
                </div>
            `;
            container.appendChild(div);
        });

    } catch (e) {
        console.error("History load error:", e);
    }
}

async function loadAnalytics() {
    try {
        const res = await fetch('/api/summary');
        const stats = await res.json();

        // App Usage
        const list = document.getElementById('app-usage-list');
        list.innerHTML = '';
        stats.top_apps.forEach(app => {
            const li = document.createElement('li');
            li.innerText = `${app.name}: ${Math.round(app.seconds)} sec`;
            list.appendChild(li);
        });

    } catch (e) {
        console.error("Analytics error:", e);
    }
}

async function initChart() {
    const ctx = document.getElementById('riskChart').getContext('2d');
    chartInstance = new Chart(ctx, {
        type: 'line',
        data: {
            labels: [],
            datasets: [{
                label: 'Total Risk',
                data: [],
                borderColor: '#3b82f6',
                tension: 0.4
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            scales: { y: { beginAtZero: true, max: 100 } }
        }
    });

    setInterval(async () => {
        // Only update chart if tab is live
        if (currentTab !== 'live') return;
        const res = await fetch('/api/history');
        const hist = await res.json();
        if (!hist.length) return;
        chartInstance.data.labels = hist.map(h => `Cycle ${h.id}`);
        chartInstance.data.datasets[0].data = hist.map(h => (h.total_risk || 0) * 100);
        chartInstance.update();
    }, 2000);
}

window.addEventListener('load', () => {
    initChart();
    setInterval(updateDashboard, REFRESH_RATE);
});
