/*====================================================
ADMIN - SALES MANAGEMENT LOGIC

Handles:
1. Rendering price list table
2. Inline price editing
3. Rendering products table
4. Adding new products
5. Search filtering on both tabs
6. Tab switching
=====================================================*/

/*-------- Admin price store -------- 
Start with the sample price from the dashboard. Admin can update these.*/
const adminPrices = {
    "wines"  : 42500,
    "spirits"  : 9500,
    "bitters"  : 18000,
    "beer-stout"  : 12500,
    "malt-drink"  : 8400,
    "rtd-energy" : 26000

};

/*-------- Category display labels --------- */
const adminCategoryLabels = {
    "wines"    :   "Wines",
    "spirits"  :  "Spirits",
    "bitters"   : "Beer & Stout",
    "malt-drinks"  : "Malt Drink",
    "rtd-energy"   : "RTD & Energy",
};

/*-------- Format price for display ---------- */
 function formatPrice(amount) {
    return "₦" + Number(amount). toLocaleString();
 }

 /*------- Tab switching -------  */
 function switchTab(tab) {

    //update tab button styles
    document.getElementById("tab-prices")
    .classList.remove("active");
    document.getElementById("tab-products")



 }