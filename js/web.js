document.addEventListener("DOMContentLoaded", function () {
    fetch("components/navbar.html")
    .then(response => response.text ())
    .then(data => {
        document.getElementById("navbar").innerHTML = data;
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