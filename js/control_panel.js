/*=========================================
CONTROL PANEL - OWNER MONITORING LOGIC
==========================================*/

const changeLog = [
    {
        datetime : "2026-05-12 09:14",
        manager  : "Chukwuemeka",
        branch   : "Owerri",
        product  : "Heineken RGB - 60cl",
        category : "Beer & Stout",
        oldPrice : 12000,
        newPrice : 12500
    },
    {
        datetime : "2026-05-12 10:32",
        manager  : "Adaeze",
        branch   : "Onitsha",
        product  : "Four Cousins Sweet Red",
        category : "Wines",
        oldPrice : 40000,
        newPrice : 42500
    },
    {
        datetime : "2026-05-11 14:05",
        manager  : "Emeka",
        branch   : "Port Harcourt",
        product  : "Hennessy VS - 75cl",
        category : "Spirits",
        oldPrice : 90000,
        newPrice : 95000
    },
    {
        datetime : "2026-05-11 11:22",
        manager  : "Chukwuemeka",
        branch   : "Owerri",
        product  : "Star Lager RGB",
        category : "Beer & Stout",
        oldPrice : 9500,
        newPrice : 9800
    },
    {
        datetime : "2026-05-10 16:48",
        manager  : "Ngozi",
        branch   : "Ikeja Lagos",
        product  : "Maltina RGB",
        category : "Malt Drinks",
        oldPrice : 8000,
        newPrice : 8400
    },
    {
        datetime : "2026-05-10 09:30",
        manager  : "Adaeze",
        branch   : "Onitsha",
        product  : "Red Bull Energy - 250ml",
        category : "RTD & Energy",
        oldPrice : 24000,
        newPrice : 26000
    },
    {
        datetime : "2026-05-09 15:10",
        manager  : "Emeka",
        branch   : "Port Harcourt",
        product  : "Jigga Bitters - 750ml",
        category : "Bitters",
        oldPrice : 17000,
        newPrice : 18000
    },
    {
        datetime : "2026-05-09 10:05",
        manager  : "Ngozi",
        branch   : "Ikeja Lagos",
        product  : "Gordon's Dry Gin - 75cl",
        category : "Spirits",
        oldPrice : 92000,
        newPrice : 95000
    }
];

function cpFormatPrice(amount) {
    return "₦" + Number(amount).toLocaleString();
}

function formatChange(oldPrice, newPrice) {
    const diff    = newPrice - oldPrice;
    const percent = ((diff / oldPrice) * 100).toFixed(1);
    const sign    = diff > 0 ? "+" : "";
    const color   = diff > 0 ? "#8b1d1d" : "#0d5c2f";

    return `<span style="color:${color}; font-weight:700;">
        ${sign}${percent}%
    </span>`;
}


function renderKPIs() {

    document.getElementById("kpi-products").textContent
        = products.length;

    document.getElementById("kpi-updates").textContent
        = changeLog.length;

    document.getElementById("kpi-last").textContent
        = changeLog[0].datetime;

    const managers = [...new Set(
        changeLog.map(function (c) { return c.manager; })
    )];
    document.getElementById("kpi-managers").textContent
        = managers.length;
}

function renderFeed() {

    const feed = document.getElementById("cp-feed");

    feed.innerHTML = changeLog.slice(0, 6).map(function (c) {

        const diff  = c.newPrice - c.oldPrice;
        const color = diff > 0 ? "#8b1d1d" : "#0d5c2f";

        return `
            <div class="cp-feed-item">
                <div class="cp-feed-dot"
                    style="background:${color};"></div>
                <div class="cp-feed-content">
                    <p class="cp-feed-text">
                        <strong>${c.manager}</strong>
                        updated <strong>${c.product}</strong>
                        from ${cpFormatPrice(c.oldPrice)}
                        to ${cpFormatPrice(c.newPrice)}
                    </p>
                    <p class="cp-feed-meta">
                        ${c.branch} &middot; ${c.datetime}
                    </p>
                </div>
            </div>
        `;
    }).join("");
}

function renderSummary() {

    const highest = changeLog.reduce(function (max, c) {
        return (c.newPrice - c.oldPrice) >
            (max.newPrice - max.oldPrice) ? c : max;
    });
    document.getElementById("summary-highest").textContent
        = highest.product;

    const managerCount = {};
    changeLog.forEach(function (c) {
        managerCount[c.manager] =
            (managerCount[c.manager] || 0) + 1;
    });
    const topManager = Object.keys(managerCount).reduce(
        function (a, b) {
            return managerCount[a] > managerCount[b] ? a : b;
        }
    );
    document.getElementById("summary-manager").textContent
        = topManager + " (" + managerCount[topManager] + " changes)";

    const categoryCount = {};
    changeLog.forEach(function (c) {
        categoryCount[c.category] =
            (categoryCount[c.category] || 0) + 1;
    });
    const topCategory = Object.keys(categoryCount).reduce(
        function (a, b) {
            return categoryCount[a] > categoryCount[b] ? a : b;
        }
    );
    document.getElementById("summary-category").textContent
        = topCategory;

    const totalChange = changeLog.reduce(function (sum, c) {
        return sum + (c.newPrice - c.oldPrice);
    }, 0);
    document.getElementById("summary-value").textContent
        = cpFormatPrice(totalChange);
}


function renderLog(filter) {

    const tbody  = document.getElementById("log-tbody");
    const search = filter ? filter.toLowerCase().trim() : "";

    let list = changeLog;

    if (search !== "") {
        list = list.filter(function (c) {
            return c.product.toLowerCase().includes(search)
                || c.manager.toLowerCase().includes(search)
                || c.branch.toLowerCase().includes(search);
        });
    }

    if (list.length === 0) {
        tbody.innerHTML = `
            <tr>
                <td colspan="8" class="admin-empty">
                    No records found.
                </td>
            </tr>
        `;
        return;
    }

    tbody.innerHTML = list.map(function (c) {
        return `
            <tr>
                <td>${c.datetime}</td>
                <td><strong>${c.manager}</strong></td>
                <td>${c.branch}</td>
                <td class="admin-td-name">${c.product}</td>
                <td>${c.category}</td>
                <td>${cpFormatPrice(c.oldPrice)}</td>
                <td>${cpFormatPrice(c.newPrice)}</td>
                <td>${formatChange(c.oldPrice, c.newPrice)}</td>
            </tr>
        `;
    }).join("");
}

document.getElementById("log-search")
    .addEventListener("input", function () {
        renderLog(this.value);
    });

document.addEventListener("DOMContentLoaded", function () {
    renderKPIs();
    renderFeed();
    renderSummary();
    renderLog();
});