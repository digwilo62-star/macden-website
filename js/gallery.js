/*=========================================
GALLERY — DATA, CAROUSEL, LIGHTBOX

To add a new photo:
1. Drop image into images/gallery/
2. Add one entry to galleryImages

Features:
- 1 image visible at a time (desktop + mobile)
- Swipe (touch + mouse drag) with click/drag separation
- Auto-advance every 5s, pauses on hover/interaction
- Lightbox with swipe nav, swipe-down to dismiss
==========================================*/


const galleryImages = [
    { src: "images/gallery/photo-01.jpg", label: "Lagos Trade Fair 2024" },
    { src: "images/gallery/photo-02.jpg", label: "Best Distributor Award — Owerri" },
    { src: "images/gallery/photo-03.jpg", label: "Port Harcourt Distribution Summit" },
    { src: "images/gallery/photo-04.jpg", label: "MACDEN Team — Onitsha Branch" },
    { src: "images/gallery/photo-05.jpg", label: "Anambra Beverage Expo 2023" },
    { src: "images/gallery/photo-06.jpg", label: "Top Supplier Recognition — Lagos" },
    { src: "images/gallery/photo-07.jpg", label: "Warehouse Operations — Owerri" },
    { src: "images/gallery/photo-08.jpg", label: "Industry Partners Dinner 2024" },
    { src: "images/gallery/photo-09.jpg", label: "MACDEN Fleet — Port Harcourt" }
];


const AUTO_ADVANCE_MS  = 5000;
const SWIPE_THRESHOLD  = 50;
const CLICK_THRESHOLD  = 8;   // movement under this = click, not drag


let currentSlide   = 0;
let lightboxIndex  = 0;
let autoAdvanceId  = null;


/*-------- Build cards (1 visible at a time) --------*/
function buildCarouselCards() {
    const track = document.getElementById("carousel-track");

    track.innerHTML = galleryImages.map(function (img, index) {
        return `
            <div class="carousel-card" data-index="${index}">
                <div class="carousel-card-img"
                    style="background-image: url('${img.src}');">
                    <div class="carousel-card-overlay"></div>
                    <p class="carousel-card-label">${img.label}</p>
                </div>
            </div>
        `;
    }).join("");
}


/*-------- One dot per image --------*/
function buildDots() {
    const dotsWrap = document.getElementById("carousel-dots");

    dotsWrap.innerHTML = galleryImages.map(function (_, i) {
        return `<span class="carousel-dot ${i === 0 ? "active" : ""}" data-slide="${i}"></span>`;
    }).join("");

    dotsWrap.querySelectorAll(".carousel-dot").forEach(function (dot) {
        dot.addEventListener("click", function () {
            goToSlide(parseInt(dot.dataset.slide, 10));
            resetAutoAdvance();
        });
    });
}


/*-------- Show/hide cards (only one visible) --------*/
function updateCarousel() {
    const cards = document.querySelectorAll(".carousel-card");
    cards.forEach(function (card, index) {
        card.style.display = index === currentSlide ? "block" : "none";
    });

    document.querySelectorAll(".carousel-dot").forEach(function (dot, i) {
        dot.classList.toggle("active", i === currentSlide);
    });
}


/*-------- Navigate (wraps around for smooth auto-advance) --------*/
function goToSlide(index) {
    const total = galleryImages.length;
    currentSlide = ((index % total) + total) % total;   // wrap negative too
    updateCarousel();
}


/*-------- Auto-advance --------*/
function startAutoAdvance() {
    stopAutoAdvance();
    autoAdvanceId = setInterval(function () {
        goToSlide(currentSlide + 1);
    }, AUTO_ADVANCE_MS);
}

function stopAutoAdvance() {
    if (autoAdvanceId) {
        clearInterval(autoAdvanceId);
        autoAdvanceId = null;
    }
}

function resetAutoAdvance() {
    startAutoAdvance();
}


/*-------- Arrows --------*/
document.getElementById("carousel-prev").addEventListener("click", function () {
    goToSlide(currentSlide - 1);
    resetAutoAdvance();
});

document.getElementById("carousel-next").addEventListener("click", function () {
    goToSlide(currentSlide + 1);
    resetAutoAdvance();
});


/*-------- Swipe + drag with click/drag separation --------*/
(function bindCarouselSwipe() {
    const track = document.getElementById("carousel-track");

    let startX = 0;
    let startY = 0;
    let isPointerDown = false;
    let hasMoved = false;

    function onStart(x, y) {
        startX = x;
        startY = y;
        isPointerDown = true;
        hasMoved = false;
        stopAutoAdvance();
    }

    function onMove(x, y) {
        if (!isPointerDown) return;
        const dx = Math.abs(x - startX);
        const dy = Math.abs(y - startY);
        if (dx > CLICK_THRESHOLD || dy > CLICK_THRESHOLD) {
            hasMoved = true;
        }
    }

    function onEnd(x) {
        if (!isPointerDown) return;
        isPointerDown = false;

        const delta = x - startX;

        if (Math.abs(delta) > SWIPE_THRESHOLD) {
            goToSlide(currentSlide + (delta < 0 ? 1 : -1));
        }
        startAutoAdvance();
    }

    /* Touch */
    track.addEventListener("touchstart", function (e) {
        onStart(e.touches[0].clientX, e.touches[0].clientY);
    }, { passive: true });

    track.addEventListener("touchmove", function (e) {
        onMove(e.touches[0].clientX, e.touches[0].clientY);
    }, { passive: true });

    track.addEventListener("touchend", function (e) {
        onEnd(e.changedTouches[0].clientX);
    });

    /* Mouse drag */
    track.addEventListener("mousedown", function (e) {
        onStart(e.clientX, e.clientY);
    });

    track.addEventListener("mousemove", function (e) {
        onMove(e.clientX, e.clientY);
    });

    track.addEventListener("mouseup", function (e) {
        onEnd(e.clientX);
    });

    track.addEventListener("mouseleave", function (e) {
        if (isPointerDown) onEnd(e.clientX);
    });

    /* Click → open lightbox ONLY if no drag happened.
       Bound on the track and uses data-index from the card. */
    track.addEventListener("click", function (e) {
        if (hasMoved) {
            hasMoved = false;
            e.preventDefault();
            e.stopPropagation();
            return;
        }
        const card = e.target.closest(".carousel-card");
        if (!card) return;
        const idx = parseInt(card.dataset.index, 10);
        openLightbox(idx);
    });
})();


/*-------- Pause auto-advance on hover --------*/
(function bindCarouselHover() {
    const carousel = document.querySelector(".gallery-carousel");
    if (!carousel) return;
    carousel.addEventListener("mouseenter", stopAutoAdvance);
    carousel.addEventListener("mouseleave", startAutoAdvance);
})();


/*========== LIGHTBOX ==========*/

function openLightbox(index) {
    lightboxIndex = index;
    updateLightbox();
    document.getElementById("lightbox").classList.add("lightbox--open");
    document.body.style.overflow = "hidden";
    stopAutoAdvance();
}

function closeLightbox() {
    document.getElementById("lightbox").classList.remove("lightbox--open");
    document.body.style.overflow = "";
    startAutoAdvance();
}

function updateLightbox() {
    const img = galleryImages[lightboxIndex];
    document.getElementById("lightbox-img").src         = img.src;
    document.getElementById("lightbox-img").alt         = img.label;
    document.getElementById("lightbox-caption").textContent = img.label;
    document.getElementById("lightbox-counter").textContent =
        (lightboxIndex + 1) + " of " + galleryImages.length;
}

function lightboxNext() {
    lightboxIndex = (lightboxIndex + 1) % galleryImages.length;
    updateLightbox();
}

function lightboxPrev() {
    lightboxIndex = (lightboxIndex - 1 + galleryImages.length) % galleryImages.length;
    updateLightbox();
}


document.getElementById("lightbox-prev").addEventListener("click", lightboxPrev);
document.getElementById("lightbox-next").addEventListener("click", lightboxNext);
document.getElementById("lightbox-close").addEventListener("click", closeLightbox);
document.getElementById("lightbox-overlay").addEventListener("click", closeLightbox);


/*-------- Swipe inside lightbox --------*/
(function bindLightboxSwipe() {
    const imgWrap = document.querySelector(".lightbox-img-wrap");
    if (!imgWrap) return;

    let sx = 0, sy = 0;
    let down = false;

    function start(x, y) { sx = x; sy = y; down = true; }
    function end(x, y) {
        if (!down) return;
        down = false;
        const dx = x - sx;
        const dy = y - sy;
        if (Math.abs(dx) > SWIPE_THRESHOLD && Math.abs(dx) > Math.abs(dy)) {
            dx < 0 ? lightboxNext() : lightboxPrev();
        } else if (dy > SWIPE_THRESHOLD * 1.5 && Math.abs(dy) > Math.abs(dx)) {
            closeLightbox();
        }
    }

    imgWrap.addEventListener("touchstart", function (e) {
        start(e.touches[0].clientX, e.touches[0].clientY);
    }, { passive: true });
    imgWrap.addEventListener("touchend", function (e) {
        end(e.changedTouches[0].clientX, e.changedTouches[0].clientY);
    });
})();


/*-------- Keyboard --------*/
document.addEventListener("keydown", function (e) {
    const lb = document.getElementById("lightbox");
    if (!lb.classList.contains("lightbox--open")) return;

    if (e.key === "ArrowLeft")  lightboxPrev();
    if (e.key === "ArrowRight") lightboxNext();
    if (e.key === "Escape")     closeLightbox();
});


/*========== INIT ==========*/

document.addEventListener("DOMContentLoaded", function () {
    buildCarouselCards();
    buildDots();
    updateCarousel();
    startAutoAdvance();
});


/*-------- On resize: just rebuild dots (in case layout shifts) --------*/
window.addEventListener("resize", function () {
    buildDots();
    updateCarousel();
});