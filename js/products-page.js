/*=========================================
PRODUCTS PAGE - RENDERING + FILTER + SEARCH

Reads the global products array (products.js)
and renders cards into #products-grid.

Features:
- Live search as user types
- Category filter chips
- Product count display
- Empty state with clear button
==========================================*/

/*-------- Category display labels --------*/
const categoryLabels = {
    "wines"      : "Wines",
    "spirits"    : "Spirits",
    "bitters"    : "Bitters",
    "beer-stout" : "Beer & Stout",
    "malt-drinks": "Malt Drinks",
    "rtd-energy" : "RTD & Energy"
};

/*-------- Build a single product card --------*/
function buildProductCard(product) {

    const categoryDisplay = categoryLabels[product.category]
        || product.category;

    return `
        <div class="product-card">
            <div class="product-card-accent"></div>
            <div class="product-card-body">
                <p class="product-category-label">
                    ${categoryDisplay}
                </p>
                <h3 class="product-name">
                    ${product.name}
                </h3>
                <p class="product-unit">
                    ${product.unit}
                </p>
                <a href="login.html"
                    class="product-lock-btn">
                    &#128274; Sign in for price
                </a>
            </div>
        </div>
    `;
}

/*-------- Update product count label --------*/
function updateCount(list, category, search) {

    const count = document.getElementById("products-count");
    const total = list.length;

    if (search !== "") {
        count.textContent = total === 0
            ? "No results for \"" + search + "\""
            : total + " result" +
              (total === 1 ? "" : "s") +
              " for \"" + search + "\"";
    } else if (category !== "all") {
        const label = categoryLabels[category] || category;
        count.textContent = "Showing " + total +
            " " + label + " product" +
            (total === 1 ? "" : "s");
    } else {
        count.textContent = "Showing all " +
            total + " products";
    }
}

/*-------- Render products into the grid --------*/
function renderProducts(list, category, search) {

    const grid    = document.getElementById("products-grid");
    const loading = document.getElementById("products-loading");
    const empty   = document.getElementById("products-empty");

    loading.hidden = true;

    if (list.length === 0) {
        grid.innerHTML = "";
        empty.hidden   = false;
    } else {
        empty.hidden   = true;
        grid.innerHTML = list.map(buildProductCard).join("");
    }

    updateCount(list, category || "all", search || "");
}

/*-------- Apply both filters together --------*/
function applyFilters() {

    const activeChip = document.querySelector(
        ".filter-chip.active"
    );
    const category = activeChip
        ? activeChip.dataset.category : "all";

    const searchInput = document.getElementById(
        "products-search"
    );
    const search = searchInput
        ? searchInput.value.toLowerCase().trim() : "";

    // Show or hide clear button
    const clearBtn = document.getElementById("search-clear-btn");
    if (clearBtn) {
        clearBtn.style.display = search !== "" ? "block" : "none";
    }

    let filtered = products;

    // Category filter
    if (category !== "all") {
        filtered = filtered.filter(function (p) {
            return p.category === category;
        });
    }

    // Search filter
    if (search !== "") {
        filtered = filtered.filter(function (p) {
            return p.name.toLowerCase().includes(search);
        });
    }

    renderProducts(filtered, category, search);
}

/*-------- Wire up filter chips --------*/
document.querySelectorAll(".filter-chip")
    .forEach(function (chip) {
        chip.addEventListener("click", function () {
            document.querySelectorAll(".filter-chip")
                .forEach(function (c) {
                    c.classList.remove("active");
                });
            chip.classList.add("active");
            applyFilters();
        });
    });

/*-------- Wire up search input --------*/
const searchInput = document.getElementById("products-search");
if (searchInput) {
    searchInput.addEventListener("input", function () {
        applyFilters();
    });
}

/*-------- Wire up search clear button --------*/
const searchClearBtn = document.getElementById("search-clear-btn");
if (searchClearBtn) {
    searchClearBtn.addEventListener("click", function () {
        document.getElementById("products-search").value = "";
        applyFilters();
    });
}

/*-------- Wire up empty state clear button --------*/
const emptyClearBtn = document.getElementById("empty-clear-btn");
if (emptyClearBtn) {
    emptyClearBtn.addEventListener("click", function () {
        document.getElementById("products-search").value = "";
        document.querySelectorAll(".filter-chip")
            .forEach(function (c) {
                c.classList.remove("active");
            });
        document.querySelector(
            ".filter-chip[data-category='all']"
        ).classList.add("active");
        applyFilters();
    });
}

/*-------- Initial render --------*/
document.addEventListener("DOMContentLoaded", function () {
    applyFilters();
});