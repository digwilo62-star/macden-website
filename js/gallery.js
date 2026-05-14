/*=========================================
GALLERY DATA + CAROUSEL + LIGHTBOX LOGIC

All gallery images live in this file.
To add a new photo:
1. Drop the image into images/gallery/
2. Add one entry to the galleryImages array

The carousel and lightbox read from this
array automatically. No other changes needed.
==========================================*/

/*-------- Gallery images --------*/
const galleryImages = [
    {
        src   : "images/gallery/photo-01.jpg",
        label : "Lagos Trade Fair 2024"
    },
    {
        src   : "images/gallery/photo-02.jpg",
        label : "Best Distributor Award — Owerri"
    },
    {
        src   : "images/gallery/photo-03.jpg",
        label : "Port Harcourt Distribution Summit"
    },
    {
        src   : "images/gallery/photo-04.jpg",
        label : "MACDEN Team — Onitsha Branch"
    },
    {
        src   : "images/gallery/photo-05.jpg",
        label : "Anambra Beverage Expo 2023"
    },
    {
        src   : "images/gallery/photo-06.jpg",
        label : "Top Supplier Recognition — Lagos"
    },
    {
        src   : "images/gallery/photo-07.jpg",
        label : "Warehouse Operations — Owerri"
    },
    {
        src   : "images/gallery/photo-08.jpg",
        label : "Industry Partners Dinner 2024"
    },
    {
        src   : "images/gallery/photo-09.jpg",
        label : "MACDEN Fleet — Port Harcourt"
    }
];

/*-------- Carousel state --------*/
let currentSlide  = 0;
let lightboxIndex = 0;

function getVisibleCount() {
    return window.innerWidth <= 768 ? 1 : 3;
}

/*-------- Build carousel cards --------*/
function buildCarouselCards() {

    const track = document.getElementById("carousel-track");

    track.innerHTML = galleryImages.map(function (img, index) {
        return `
            <div class="carousel-card"
                onclick="openLightbox(${index})">
                <div class="carousel-card-img"
                    style="background-image:
                        url('${img.src}');">
                    <div class="carousel-card-overlay"></div>
                    <p class="carousel-card-label">
                        ${img.label}
                    </p>
                </div>
            </div>
        `;
    }).join("");
}

/*-------- Build dots --------*/
function buildDots() {

    const dotsWrap  = document.getElementById("carousel-dots");
    const totalDots = Math.ceil(
        galleryImages.length / getVisibleCount()
    );

    dotsWrap.innerHTML = Array.from(
        { length: totalDots },
        function (_, i) {
            return `
                <span class="carousel-dot
                    ${i === 0 ? "active" : ""}"
                    onclick="goToSlide(${i})">
                </span>
            `;
        }
    ).join("");
}

/*-------- Update carousel position --------*/
function updateCarousel() {

    const track  = document.getElementById("carousel-track");
    const offset = currentSlide * getVisibleCount();
    const cards  = track.querySelectorAll(".carousel-card");

    cards.forEach(function (card, index) {
        card.style.display =
            (index >= offset &&
             index < offset + getVisibleCount())
            ? "block" : "none";
    });

    document.querySelectorAll(".carousel-dot")
        .forEach(function (dot, i) {
            dot.classList.toggle("active", i === currentSlide);
        });
}

/*-------- Navigate carousel --------*/
function goToSlide(index) {
    const maxSlide = Math.ceil(
        galleryImages.length / getVisibleCount()
    ) - 1;
    currentSlide = Math.max(0, Math.min(index, maxSlide));
    updateCarousel();
}

/*-------- Arrow listeners --------*/
document.getElementById("carousel-prev")
    .addEventListener("click", function () {
        goToSlide(currentSlide - 1);
    });

document.getElementById("carousel-next")
    .addEventListener("click", function () {
        goToSlide(currentSlide + 1);
    });

/*-------- Open lightbox --------*/
function openLightbox(index) {
    lightboxIndex = index;
    updateLightbox();
    document.getElementById("lightbox")
        .classList.add("lightbox--open");
    document.body.style.overflow = "hidden";
}

/*-------- Close lightbox --------*/
function closeLightbox() {
    document.getElementById("lightbox")
        .classList.remove("lightbox--open");
    document.body.style.overflow = "";
}

/*-------- Update lightbox content --------*/
function updateLightbox() {

    const img     = galleryImages[lightboxIndex];
    const counter = (lightboxIndex + 1) +
        " of " + galleryImages.length;

    document.getElementById("lightbox-img").src
        = img.src;
    document.getElementById("lightbox-img").alt
        = img.label;
    document.getElementById("lightbox-caption")
        .textContent = img.label;
    document.getElementById("lightbox-counter")
        .textContent = counter;
}

/*-------- Lightbox navigation --------*/
document.getElementById("lightbox-prev")
    .addEventListener("click", function () {
        lightboxIndex = (lightboxIndex - 1 +
            galleryImages.length) %
            galleryImages.length;
        updateLightbox();
    });

document.getElementById("lightbox-next")
    .addEventListener("click", function () {
        lightboxIndex =
            (lightboxIndex + 1) % galleryImages.length;
        updateLightbox();
    });

/*-------- Close on overlay click --------*/
document.getElementById("lightbox-overlay")
    .addEventListener("click", closeLightbox);

document.getElementById("lightbox-close")
    .addEventListener("click", closeLightbox);

/*-------- Keyboard navigation --------*/
document.addEventListener("keydown", function (e) {

    const lb = document.getElementById("lightbox");
    if (!lb.classList.contains("lightbox--open")) return;

    if (e.key === "ArrowLeft") {
        lightboxIndex = (lightboxIndex - 1 +
            galleryImages.length) %
            galleryImages.length;
        updateLightbox();
    }

    if (e.key === "ArrowRight") {
        lightboxIndex =
            (lightboxIndex + 1) % galleryImages.length;
        updateLightbox();
    }

    if (e.key === "Escape") {
        closeLightbox();
    }
});

/*-------- Initial render --------*/
document.addEventListener("DOMContentLoaded", function () {
    buildCarouselCards();
    buildDots();
    updateCarousel();
});

/*-------- Rebuild on resize --------*/
window.addEventListener("resize", function () {
    buildDots();
    goToSlide(0);
});