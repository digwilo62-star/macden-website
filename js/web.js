document.addEventListener("DOMContentLoaded", function () {
    fetch("components/navbar.html")
        .then(response => response.text())
        .then(data => {
            document.getElementById("navbar").innerHTML = data;
            // Set body padding to match the real navbar height
const setNavOffset = () => {
    const nav = document.querySelector(".navbar");
    if (nav) {
        const navHeight = nav.offsetHeight;
        document.body.style.paddingTop = navHeight + "px";

        /* Also update sticky search bar on products page */
        const searchBar = document.querySelector(
            ".prod-search-bar"
        );
        if (searchBar) {
            searchBar.style.top = navHeight + "px";
        }
    }
};

setNavOffset();
window.addEventListener("resize", function () {
    clearTimeout(window._navResizeTimer);
    window._navResizeTimer = setTimeout(setNavOffset, 150);
});

            // Default empty path to index.html so the home link highlights
            let currentPage = window.location.pathname.split("/").pop();
            if (!currentPage) currentPage = "index.html";

            document.querySelectorAll(".nav-links a").forEach(link => {
                if (link.getAttribute("href") === currentPage) {
                    link.classList.add("active");
                }

            });
        })
        .catch(error => console.error("Error loading navbar:", error));
});

//footer
fetch('components/footer.html')
.then(r => r.text())
.then(html => {
    document.getElementById('footer').innerHTML = html;
});

// Fade-in on scroll
const fadeElements = document.querySelectorAll(".fade-in");
const observer = new IntersectionObserver((entries, obs) => {
    entries.forEach(entry => {
        if (entry.isIntersecting) {
            entry.target.classList.add("show");
            obs.unobserve(entry.target); // stop watching once shown
        }
    });
}, { threshold: 0.15 });

fadeElements.forEach(el => observer.observe(el));

// Navbar shrink on scroll — cache the reference
const navbar = document.querySelector(".nav-container");

window.addEventListener("scroll", function () {
    if (!navbar) return;

    if (window.scrollY > 40) {
        navbar.style.padding = "12px 24px";
        navbar.style.borderRadius = "14px";
    } else {
        navbar.style.padding = "16px 28px";
        navbar.style.borderRadius = "18px";
    }
});