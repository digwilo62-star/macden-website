/*=========================================
PRODUCTS PAGE - RENDERING LOGIC

Read the global products array (from products.js)
and renders each product a card inside the 
#products-grid element.

This files does NOT contain the data itself - that 
lives in product.js. keeping data and logic separate 
makes either one easy to change without touching 
the other 
=======================================*/


/*--------- Category display labels--------------------
Map the lowercase category keys (used in the data 
and on the filter chips) to their friendly display 
label for the category badge inside each card.*/ 

const categoryLabels = {
    "wines" : "Wines",
    "spirits" : "Spirits",
    "bitters": "Bitters",
    "beer-stout" : "Beer & Stout",
    "malt-drinks" : "Malt Drinks",
    "rtd-energy" :"RTD & Energy "
};

/*------- Build a single product card--------------------
Takes one product object and returns the HTML
string for that product's card.

The backtick syntax ('...') is a template literal
it lets us drop variable values straight into the 
string with ${...}*/

function buildProductCard(product) {
    //Look up the friendly category label.
    //If the key isn't i our map, fall back to the raw key
    // so we never end up with a blank category badge.
    const categoryDisplay = categoryLabels[product.category] || product.category;

    return `   <div class="product-card">
     <div class="product-card-accent"></div>
     <div class="product-card-body">
       <p class="product-category-label">${categoryDisplay}</p>
       <h3 class="product-name">${product.name}</h3>
       <a href="login.html" class="product-price-link">Sign in for price</a> 
        </div>   
    </div>
 `;
 

}


/*----- Render all products into the grid------------------
Builds card markup for every product in the list,
joins them into a single HTML string, and injects
that string into the grid container. Then hides
the loading messages.*/

function renderProducts(productList) {

    //Find the grid and loading elements in the DOM
    const grid = document.getElementById("products-grid");
    const loading = document.getElementById("products-loading");

    //Build HTML for each card, then join into one big string.
    //.map() runs buildProductCard() on every item and returns 
    // a new array; .join ("") flattens that array into a string.
    const cardsHTML = productList.map(buildProductCard).join("");

    // Inject the cards into the grid
    grid.innerHTML = cardsHTML;

    //HIde the "loading products...." message
    loading.hidden=true;
}


/*-------Run once the page is ready-------
DOMcontentLoaded fires when the HTML is fully 
parsed. By thst point , #products-grid and 
#products-loading exist in the DOM, so we can
safely find and modify them.*/

document.addEventListener("DOMContentLoaded", function () {
    renderProducts(products);
    setupFilters();
});


/*========================================================
--------SET UP CATEGORY FILTER ---------
Wire up the filter chips at the top of the page. 
Each chip has a data-category attribute (e.g "all", "wines", "spirits"). when a chip is clicked:
1.) Mark this as active (others go inactive )
2.) Filter the products array by that category 
3.) Re-enter the grid with the filter list
4.) show/hide the empty-state message
=======================================================*/

function setupFilters() {
    //Grab every filter chip on the page
    const chips = document.querySelectorAll(".filter-chip");

    //Grab the empty-state message (shown when no matches)
    const empty = document.getElementById("products-empty");

    //Loop over each chip and attach a click listener
    chips.forEach(function (chip) {
        chip.addEventListener("click" ,function () {

            //step 1: deaactiate every chip, then activate the clicked one
            chips.forEach(function (c) {
                c.classList.remove("active");
            });
            chip.classList.add("active");

            //steo 2: read the chip's data-category attribute
            const category = chip.dataset.category;

            // step 3: filter the products list.
            // "all" shows everything; anything else keeps only matches matches.
            let filtered;
            if (category === "all") {
                filtered = products;
            }
           else {
            filtered = products.filter(function (p) {
                return p.category === category;
            });
               }

            // step 4: re-render the empty-state message
           renderProducts(filtered);

            // step 5: toggle the empty-state message.
            // only runs if the empty element exist in the HTML.
            if (empty) {
                empty.hidden = filtered.length > 0;
            }
        

        });
    });


}

