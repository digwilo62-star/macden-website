/*================================================
WEB.JS — GLOBAL SITE LOGIC

Handles:
1. Navbar loading — sessionStorage cache for speed
2. Footer loading
3. Active nav link highlighting
4. Body padding offset to clear fixed navbar
5. Sticky element offset (search bar etc)
6. Fade-in on scroll
7. Navbar shrink on scroll
8. Bottom nav active state
================================================*/


/*------------------------------------------------
NAVBAR LOADER
First visit: fetches navbar from components/navbar.html
and caches it in sessionStorage.
Every page after: reads from sessionStorage instantly.
Splits into top nav and bottom nav via <!--SPLIT--> marker.
------------------------------------------------*/

document.addEventListener("DOMContentLoaded", function () {

    const CACHE_KEY = "macden_navbar_html";
    const navbarEl  = document.getElementById("navbar");

    function initNavbar(html) {

        if (!navbarEl) return;

        /* Split navbar into top + bottom sections */
        const parts = html.split('<!--SPLIT-->');
        navbarEl.innerHTML = parts[0] || '';

        const bottomEl = document.getElementById('bottom-nav');
        if (bottomEl && parts[1]) {
            bottomEl.innerHTML = parts[1];
        }

        /* Set body padding to match navbar height */
        setNavOffset();
        window.addEventListener("resize", function () {
            clearTimeout(window._navResizeTimer);
            window._navResizeTimer = setTimeout(
                setNavOffset, 150
            );
        });

        /* Highlight active nav link */
        let currentPage = window.location.pathname
            .split("/").pop();
        if (!currentPage) currentPage = "index.html";

        document.querySelectorAll(".nav-links a")
            .forEach(function (link) {
                if (link.getAttribute("href") === currentPage) {
                    link.classList.add("active");
                }
            });

        /* Highlight active bottom nav item */
        document.querySelectorAll(".bottom-nav-item")
            .forEach(function (item) {
                const href = item.getAttribute("href");
                if (href === currentPage) {
                    item.classList.add("active");
                }
            });

        /* Navbar shrink on scroll */
        const navContainer = document.querySelector(
            ".nav-container"
        );
        window.addEventListener("scroll", function () {
            if (!navContainer) return;
            if (window.scrollY > 40) {
                navContainer.style.padding = "10px 24px";
                navContainer.style.borderRadius = "14px";
            } else {
                navContainer.style.padding = "16px 28px";
                navContainer.style.borderRadius = "18px";
            }
        });

        /* Fade-in on scroll */
        const fadeElements = document.querySelectorAll(
            ".fade-in"
        );
        const observer = new IntersectionObserver(
            function (entries, obs) {
                entries.forEach(function (entry) {
                    if (entry.isIntersecting) {
                        entry.target.classList.add("show");
                        obs.unobserve(entry.target);
                    }
                });
            },
            { threshold: 0.15 }
        );
        fadeElements.forEach(function (el) {
            observer.observe(el);
        });
    }

    /* Try sessionStorage first */
    const cached = sessionStorage.getItem(CACHE_KEY);

    if (cached) {

        /* Instant — no network request */
        initNavbar(cached);

    } else {

        /* First visit — fetch and cache */
        fetch("components/navbar.html")
            .then(function (response) {
                return response.text();
            })
            .then(function (html) {
                sessionStorage.setItem(CACHE_KEY, html);
                initNavbar(html);
            })
            .catch(function (error) {
                console.error("Navbar load error:", error);
            });
    }

    /* Footer loader */
    const footerEl = document.getElementById("footer");
    if (footerEl) {
        const FOOTER_KEY    = "macden_footer_html";
        const cachedFooter  = sessionStorage.getItem(
            FOOTER_KEY
        );

        if (cachedFooter) {
            footerEl.innerHTML = cachedFooter;
        } else {
            fetch("components/footer.html")
                .then(function (r) { return r.text(); })
                .then(function (html) {
                    sessionStorage.setItem(FOOTER_KEY, html);
                    footerEl.innerHTML = html;
                })
                .catch(function (err) {
                    console.error("Footer load error:", err);
                });
        }
    }
});


/*------------------------------------------------
SET NAV OFFSET
Sets body paddingTop and sticky element offsets
to match the actual rendered navbar height.
Called after navbar loads and on resize.
------------------------------------------------*/

function setNavOffset() {

    const nav = document.querySelector(".navbar");
    if (!nav) return;

    /* Use bounding rect for accurate visible bottom edge */
    const navRect = nav.getBoundingClientRect();
    const navBottom = navRect.bottom;

    /* Body padding — clears fixed navbar */
    document.body.style.paddingTop = navBottom + "px";

    /* Sticky search bar — top aligns to navbar's visible bottom.
       Subtract 1px so the search bar's top border tucks under
       the navbar's bottom border, eliminating the visible gap. */
    const searchBar = document.querySelector(".prod-search-bar");
    if (searchBar) {
        searchBar.style.top = (navBottom - 1) + "px";
        searchBar.style.marginTop = "0";

        /* Sticky filter chips bar — sits directly under search bar.
           Desktop only; mobile gets position:static via CSS. */
        const filterBar = document.querySelector(".prod-filter-bar");
        if (filterBar && window.innerWidth > 768) {
            const searchHeight = searchBar.offsetHeight;
            filterBar.style.top = (navBottom + searchHeight - 1) + "px";
        } else if (filterBar) {
            filterBar.style.top = "";
        }
    }
}

/* Recalculate on scroll too — navbar shrinks on scroll,
   so the offset needs to follow. Throttled via requestAnimationFrame. */
let _scrollOffsetTicking = false;
window.addEventListener("scroll", function () {
    if (!_scrollOffsetTicking) {
        window.requestAnimationFrame(function () {
            setNavOffset();
            _scrollOffsetTicking = false;
        });
        _scrollOffsetTicking = true;
    }
});