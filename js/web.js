document.addEventListener("DOMContentLoaded", function () {

    fetch("components/navbar.html")

    .then(response => response.text ())

    .then(data => {

        document.getElementById("navbar").innerHTML = data;

        const currentPage = window.location.pathname.split("/").pop();

        const navLinks = document.querySelectorAll(".nav-links a");

        navLinks.forEach((link) => {

            const linkPage = link.getAttribute("href");

            if (linkPage === currentPage) {
                link.classList.add("active");
            }
        });

    })
    .catch(error => console.error("Error loading navbar", error));
});

const fadeElements = document.querySelectorAll(".fade-in");

const observer = new IntersectionObserver((entries) => {

    entries.forEach((entry) => {
        
        if (entry.isIntersecting) {
            entry.target.classList.add("show");
        }

    });
});

fadeElements.forEach((element) => {
    observer.observe(element);
});

window.addEventListener("scroll", function () {
    
    const navbar = document.querySelector(".nav-container");

    if (!navbar) return;

    if (window.scrollY > 40) {

        navbar.style.padding = "12px 24px";
        navbar.style.borderRadius = "14px";

    } else {

        navbar.style.padding = "16px 28px";
        navbar.style.borderRadius = "18px";
    }

    });
