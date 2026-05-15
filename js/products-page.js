/*================================================
PRODUCTS PAGE — RENDERING + FILTER + SEARCH LOGIC

Handles:
1. Category counts — how many products per category
2. Jump buttons — large category shortcut buttons
3. Filter chips — horizontal scrollable chips
4. Recently viewed — mobile strip (sessionStorage)
5. Product card builder — blurred price teaser
6. Render products — grid injection
7. Apply filters — search + category combined
8. Filter FAB + bottom sheet — mobile filter panel
9. All event listeners
10. Initial render on DOMContentLoaded
================================================*/


/*------------------------------------------------
CATEGORY DATA
Labels, accent colors, and icons per category.
Used throughout card building and UI.
------------------------------------------------*/

const categoryLabels = {
    "wines"      : "Wines",
    "spirits"    : "Spirits",
    "bitters"    : "Bitters",
    "beer-stout" : "Beer & Stout",
    "malt-drinks": "Malt Drinks",
    "rtd-energy" : "RTD & Energy"
};

/* Category accent colors — used on card top strip */
const categoryColors = {
    "wines"      : "#1a1a1a",
    "spirits"    : "#1a1a1a",
    "bitters"    : "#1a1a1a",
    "beer-stout" : "#1a1a1a",
    "malt-drinks": "#1a1a1a",
    "rtd-energy" : "#1a1a1a"
};

/* Recently viewed array — max 5 items */
let recentlyViewed = [];


/*------------------------------------------------
BUILD CATEGORY COUNTS
Counts how many products exist per category.
Returns an object: { "wines": 2, "spirits": 3 }
------------------------------------------------*/

function buildCategoryCounts() {
    const counts = { all: products.length };

    Object.keys(categoryLabels).forEach(function (cat) {
        counts[cat] = products.filter(function (p) {
            return p.category === cat;
        }).length;
    });

    return counts;
}


/*------------------------------------------------
INJECT JUMP BUTTON COUNTS
Fills the count spans inside the jump buttons.
e.g. "(2)" next to each category label.
------------------------------------------------*/

function buildJumpCounts(counts) {

    Object.keys(categoryLabels).forEach(function (cat) {
        const el = document.getElementById(
            "jump-count-" + cat
        );
        if (el) {
            el.textContent = "(" + (counts[cat] || 0) + ")";
        }
    });
}


/*------------------------------------------------
INJECT CHIP COUNTS
Fills the count spans inside the filter chips.
------------------------------------------------*/

function buildChipCounts(counts) {

    const allEl = document.getElementById("chip-count-all");
    if (allEl) {
        allEl.textContent = "(" + counts.all + ")";
    }

    Object.keys(categoryLabels).forEach(function (cat) {
        const el = document.getElementById(
            "chip-count-" + cat
        );
        if (el) {
            el.textContent = "(" + (counts[cat] || 0) + ")";
        }
    });
}


/*------------------------------------------------
RECENTLY VIEWED
Stores last 5 viewed products in sessionStorage.
Renders a horizontal strip on mobile.
------------------------------------------------*/

function addToRecent(product) {

    /* Remove if already in list */
    recentlyViewed = recentlyViewed.filter(function (p) {
        return p.id !== product.id;
    });

    /* Add to front */
    recentlyViewed.unshift(product);

    /* Keep max 5 */
    if (recentlyViewed.length > 5) {
        recentlyViewed = recentlyViewed.slice(0, 5);
    }

    /* Save to sessionStorage */
    try {
        sessionStorage.setItem(
            "macden_recent",
            JSON.stringify(recentlyViewed)
        );
    } catch (e) {}

    renderRecent();
}

function loadRecent() {

    try {
        const stored = sessionStorage.getItem("macden_recent");
        if (stored) {
            recentlyViewed = JSON.parse(stored);
            renderRecent();
        }
    } catch (e) {}
}

function renderRecent() {

    const wrap  = document.getElementById("prod-recent-wrap");
    const strip = document.getElementById("prod-recent-strip");

    if (!wrap || !strip) return;

    if (recentlyViewed.length === 0) {
        wrap.style.display = "none";
        return;
    }

    wrap.style.display = "block";

    strip.innerHTML = recentlyViewed.map(function (p) {
        return `
            <div class="prod-recent-item"
                onclick="jumpToProduct('${p.id}')">
                <p class="prod-recent-name">
                    ${p.name}
                </p>
            </div>
        `;
    }).join("");
}

function jumpToProduct(productId) {

    /* Find the card in the grid and scroll to it */
    const card = document.querySelector(
        "[data-product-id='" + productId + "']"
    );
    if (card) {
        card.scrollIntoView({
            behavior : "smooth",
            block    : "center"
        });
    }
}


/*------------------------------------------------
BUILD PRODUCT CARD
Returns an HTML string for a single product card.
Includes:
- Colored top accent strip
- Category label
- Product name
- Unit
- Blurred price teaser (₦##,###)
- Lock button linking to login
------------------------------------------------*/

function buildProductCard(product) {

    const label = categoryLabels[product.category]
        || product.category;

    const accentColor = categoryColors[product.category]
        || "#1a1a1a";

    return `
        <div class="prod-card"
            data-product-id="${product.id}"
            onclick="handleCardTap('${product.id}')">

            <!-- Colored top accent strip -->
            <div class="prod-card-accent"
                style="background:${accentColor};">
            </div>

            <div class="prod-card-body">

                <!-- Category label -->
                <p class="prod-cat-label">
                    ${label.toUpperCase()}
                </p>

                <!-- Product name -->
                <h3 class="prod-name">
                    ${product.name}
                </h3>

                <!-- Unit -->
                <p class="prod-unit">
                    ${product.unit}
                </p>

                <!-- Blurred price teaser -->
                <div class="prod-price-wrap">
                    <p class="prod-price-blur">
                        &#8358;##,###
                    </p>
                    <p class="prod-price-label">
                        Login to unlock
                    </p>
                </div>

                <!-- Lock button -->
                <a href="login.html"
                    class="prod-lock-btn"
                    onclick="event.stopPropagation()">
                    &#128274; Sign in for price
                </a>

            </div>
        </div>
    `;
}


/*------------------------------------------------
HANDLE CARD TAP
Called when a product card is clicked/tapped.
Adds product to recently viewed strip.
------------------------------------------------*/

function handleCardTap(productId) {

    const product = products.find(function (p) {
        return p.id === productId;
    });

    if (product) {
        addToRecent(product);
    }
}


/*------------------------------------------------
UPDATE PRODUCT COUNT TEXT
Updates the "Showing X products" text below chips.
------------------------------------------------*/

function updateProdCount(list, category, search) {

    const count = document.getElementById("prod-count");
    if (!count) return;

    const total = list.length;

    if (search !== "") {
        count.textContent = total === 0
            ? "No results for \"" + search + "\""
            : total + " result" +
              (total === 1 ? "" : "s") +
              " for \"" + search + "\"";
        return;
    }

    if (category !== "all") {
        const label = categoryLabels[category] || category;
        count.textContent = "Showing " + total +
            " " + label +
            " product" + (total === 1 ? "" : "s");
        return;
    }

    count.textContent = "Showing all " +
        total + " products";
}


/*------------------------------------------------
RENDER PRODUCTS
Injects product cards into the grid.
Handles loading, empty, and populated states.
------------------------------------------------*/

function renderProducts(list, category, search) {

    const grid    = document.getElementById("prod-grid");
    const loading = document.getElementById("prod-loading");
    const empty   = document.getElementById("prod-empty");

    if (!grid) return;

    /* Hide loading spinner */
    if (loading) loading.hidden = true;

    if (list.length === 0) {

        /* Show empty state */
        grid.innerHTML = "";
        if (empty) empty.hidden = false;

    } else {

        /* Hide empty state, inject cards */
        if (empty) empty.hidden = true;
        grid.innerHTML = list.map(buildProductCard).join("");
    }

    updateProdCount(list, category || "all", search || "");
}


/*------------------------------------------------
APPLY FILTERS
Combines category filter + search filter.
Reads active chip and search input value.
Updates the clear button visibility.
Calls renderProducts with filtered list.
------------------------------------------------*/

function applyFilters() {

    /* Get active category */
    const activeChip = document.querySelector(
        ".prod-chip.active"
    );
    const category = activeChip
        ? activeChip.dataset.category : "all";

    /* Get search value */
    const searchInput = document.getElementById("prod-search");
    const search = searchInput
        ? searchInput.value.toLowerCase().trim() : "";

    /* Show or hide clear button */
    const clearBtn = document.getElementById(
        "prod-search-clear"
    );
    if (clearBtn) {
        clearBtn.style.display =
            search !== "" ? "flex" : "none";
    }

    /* Filter by category */
    let filtered = products;

    if (category !== "all") {
        filtered = filtered.filter(function (p) {
            return p.category === category;
        });
    }

    /* Filter by search */
    if (search !== "") {
        filtered = filtered.filter(function (p) {
            return p.name.toLowerCase().includes(search);
        });
    }

    renderProducts(filtered, category, search);
}


/*------------------------------------------------
SET ACTIVE CATEGORY
Sets the active chip and syncs the bottom sheet.
Then applies filters.
------------------------------------------------*/

function setActiveCategory(category) {

    /* Update main chips */
    document.querySelectorAll(".prod-chip")
        .forEach(function (chip) {
            chip.classList.toggle(
                "active",
                chip.dataset.category === category
            );
        });

    /* Update sheet chips */
    document.querySelectorAll(".prod-sheet-chip")
        .forEach(function (chip) {
            chip.classList.toggle(
                "active",
                chip.dataset.category === category
            );
        });

    applyFilters();
}


/*------------------------------------------------
BOTTOM SHEET
Open and close the mobile filter bottom sheet.
------------------------------------------------*/

function openSheet() {
    const sheet   = document.getElementById("prod-sheet");
    const overlay = document.getElementById(
        "prod-sheet-overlay"
    );
    if (sheet)   sheet.classList.add("prod-sheet--open");
    if (overlay) overlay.classList.add(
        "prod-sheet-overlay--open"
    );
    document.body.style.overflow = "hidden";
}

function closeSheet() {
    const sheet   = document.getElementById("prod-sheet");
    const overlay = document.getElementById(
        "prod-sheet-overlay"
    );
    if (sheet)   sheet.classList.remove("prod-sheet--open");
    if (overlay) overlay.classList.remove(
        "prod-sheet-overlay--open"
    );
    document.body.style.overflow = "";
}


/*------------------------------------------------
EVENT LISTENERS
Wire up all interactive elements.
------------------------------------------------*/

/* Main filter chips */
document.querySelectorAll(".prod-chip")
    .forEach(function (chip) {
        chip.addEventListener("click", function () {
            setActiveCategory(chip.dataset.category);
        });
    });

/* Jump buttons */
document.querySelectorAll(".prod-jump-btn")
    .forEach(function (btn) {
        btn.addEventListener("click", function () {
            setActiveCategory(btn.dataset.category);

            /* Scroll down to grid smoothly */
            const grid = document.getElementById("prod-grid");
            if (grid) {
                grid.scrollIntoView({
                    behavior : "smooth",
                    block    : "start"
                });
            }
        });
    });

/* Search input — live filter as user types */
const searchInput = document.getElementById("prod-search");
if (searchInput) {
    searchInput.addEventListener("input", function () {
        applyFilters();
    });
}

/* Search clear button */
const searchClear = document.getElementById(
    "prod-search-clear"
);
if (searchClear) {
    searchClear.addEventListener("click", function () {
        const input = document.getElementById("prod-search");
        if (input) input.value = "";
        applyFilters();
    });
}

/* Empty state clear button */
const emptyClear = document.getElementById("prod-empty-clear");
if (emptyClear) {
    emptyClear.addEventListener("click", function () {
        const input = document.getElementById("prod-search");
        if (input) input.value = "";
        setActiveCategory("all");
    });
}

/* Filter FAB — open bottom sheet */
const fab = document.getElementById("prod-filter-fab");
if (fab) {
    fab.addEventListener("click", openSheet);
}

/* Sheet close button */
const sheetClose = document.getElementById("prod-sheet-close");
if (sheetClose) {
    sheetClose.addEventListener("click", closeSheet);
}

/* Sheet overlay — close on tap outside */
const sheetOverlay = document.getElementById(
    "prod-sheet-overlay"
);
if (sheetOverlay) {
    sheetOverlay.addEventListener("click", closeSheet);
}

/* Sheet chips — select category */
document.querySelectorAll(".prod-sheet-chip")
    .forEach(function (chip) {
        chip.addEventListener("click", function () {
            document.querySelectorAll(".prod-sheet-chip")
                .forEach(function (c) {
                    c.classList.remove("active");
                });
            chip.classList.add("active");
        });
    });

/* Sheet apply button */
const sheetApply = document.getElementById("prod-sheet-apply");
if (sheetApply) {
    sheetApply.addEventListener("click", function () {

        const activeSheetChip = document.querySelector(
            ".prod-sheet-chip.active"
        );
        const category = activeSheetChip
            ? activeSheetChip.dataset.category : "all";

        setActiveCategory(category);
        closeSheet();
    });
}

/* CTA pill buttons */
const ctaLogin = document.querySelector(".prod-cta-login");
if (ctaLogin) {
    ctaLogin.addEventListener("click", function () {
        window.location = "login.html";
    });
}

const ctaRegister = document.querySelector(
    ".prod-cta-register"
);
if (ctaRegister) {
    ctaRegister.addEventListener("click", function () {
        window.location = "register.html";
    });
}


/*------------------------------------------------
INITIAL RENDER
Runs on page load.
Builds counts, injects UI, loads recent, renders.
------------------------------------------------*/

document.addEventListener("DOMContentLoaded", function () {

    /* Build category counts */
    const counts = buildCategoryCounts();

    /* Inject counts into jump buttons */
    buildJumpCounts(counts);

    /* Inject counts into filter chips */
    buildChipCounts(counts);

    /* Load recently viewed from sessionStorage */
    loadRecent();

    /* Render all products */
    applyFilters();

    
});