/*=========================================
DASHBOARD - MAIN LOGIC
==========================================*/

let selectedProducts = [];
let currentFiltered = [];

const dashCategoryLabels = {
    "wines"      : "WINES",
    "spirits"    : "SPIRITS",
    "bitters"    : "BITTERS",
    "beer-stout" : "BEER & STOUT",
    "malt-drinks": "MALT DRINKS",
    "rtd-energy" : "RTD & ENERGY"
};

const samplePrices = {
    "wines"      : "₦42,500 / Tray",
    "spirits"    : "₦95,000 / Carton",
    "bitters"    : "₦18,000 / Carton",
    "beer-stout" : "₦12,500 / Crate",
    "malt-drinks": "₦8,400 / Crate",
    "rtd-energy" : "₦26,000 / Tray"
};

function buildDashCard(product) {

    const categoryLabel = dashCategoryLabels[product.category]
        || product.category.toUpperCase();

    const price = samplePrices[product.category] || "Price on request";

    const isSelected = selectedProducts.some(function (p) {
        return p.id === product.id;
    });

    const selectedClass = isSelected ? "dash-card--selected" : "";
    const btnText = isSelected ? "&#10003; Selected" : "+ Select";
    const btnClass = isSelected
        ? "dash-select-btn dash-select-btn--active"
        : "dash-select-btn";

    return `
        <div class="dash-card ${selectedClass}"
            data-id="${product.id}">
            <div class="dash-card-accent"></div>
            <div class="dash-card-body">
                <p class="dash-card-category">${categoryLabel}</p>
                <h3 class="dash-card-name">${product.name}</h3>
                <div class="dash-card-footer">
                    <p class="dash-card-price">${price}</p>
                    <button class="${btnClass}"
                        onclick="toggleSelect('${product.id}')">
                        ${btnText}
                    </button>
                </div>
            </div>
        </div>
    `;
}

function renderDashProducts(list) {

    const grid    = document.getElementById("dash-grid");
    const loading = document.getElementById("dash-loading");
    const empty   = document.getElementById("dash-empty");

    loading.hidden = true;

    if (list.length === 0) {
        grid.innerHTML = "";
        empty.hidden   = false;
    } else {
        empty.hidden   = true;
        grid.innerHTML = list.map(buildDashCard).join("");
    }
}

function toggleSelect(productId) {

    const product = products.find(function (p) {
        return p.id === productId;
    });

    const alreadySelected = selectedProducts.some(function (p) {
        return p.id === productId;
    });

    if (alreadySelected) {
        selectedProducts = selectedProducts.filter(function (p) {
            return p.id !== productId;
        });
    } else {
        selectedProducts.push(product);
    }

    renderDashProducts(currentFiltered);
    updateSelectionBar();
}

function updateSelectionBar() {

    const bar   = document.getElementById("dash-selection-bar");
    const count = document.getElementById("dash-selected-count");

    count.textContent = selectedProducts.length;

    if (selectedProducts.length > 0) {
        bar.classList.add("dash-selection-bar--visible");
    } else {
        bar.classList.remove("dash-selection-bar--visible");
    }
}

function applyFilters() {

    const activeChip = document.querySelector(".dash-chip.active");
    const category   = activeChip ? activeChip.dataset.category : "all";
    const search     = document.getElementById("dash-search")
        .value.toLowerCase().trim();

    let filtered = products;

    if (category !== "all") {
        filtered = filtered.filter(function (p) {
            return p.category === category;
        });
    }

    if (search !== "") {
        filtered = filtered.filter(function (p) {
            return p.name.toLowerCase().includes(search);
        });
    }

    currentFiltered = filtered;
    renderDashProducts(currentFiltered);
}

document.querySelectorAll(".dash-chip").forEach(function (chip) {
    chip.addEventListener("click", function () {
        document.querySelectorAll(".dash-chip").forEach(function (c) {
            c.classList.remove("active");
        });
        chip.classList.add("active");
        applyFilters();
    });
});

document.getElementById("dash-search")
    .addEventListener("input", function () {
        applyFilters();
    });

document.getElementById("dash-clear-btn")
    .addEventListener("click", function () {
        selectedProducts = [];
        renderDashProducts(currentFiltered);
        updateSelectionBar();
    });

document.addEventListener("DOMContentLoaded", function () {
    currentFiltered = products;
    renderDashProducts(currentFiltered);
});