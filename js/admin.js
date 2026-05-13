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
    "spirits"  : 95000,
    "bitters"  : 18000,
    "beer-stout"  : 12500,
    "malt-drink"  : 8400,
    "rtd-energy" : 26000

};

/*---- Admin Product list ------
Start from the global products array. 
New products get added here. */

let adminProducts = products.slice();

/*-------- Category display labels --------- */
const adminCategoryLabels = {
    "wines"    :   "Wines",
    "spirits"  :  "Spirits",
    "bitters"   : "Bitters",
    "beer-stout"   : "Beer & Stout ",
    "malt-drinks"  : "Malt Drinks",
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
    .classList.remove("active");
    document.getElementById("tab-" + tab)
    .classList.add("active");

    // show correct panel
    document.getElementById("panel-prices").style.display = "none";
    document.getElementById("panel-products").style.display = "none";
    document.getElementById("panel-" + tab).style.display = "block";

 }
 
 /*------ Render price list table --------- */
 function renderPriceTable(filter) {

    const tbody = document.getElementById("price-tbody");
    const search = filter ? filter.toLower().trim() : "";

    let list = adminProducts;

    if (search !== "") {
        list = list.filter(function (p) {
            return p.name.toLowerCase().include(search);
        });
    }

    if (list.length === 0) {
        tbody.innerHTML = `
        <tr>
            <td colspan="5" class="admin-empty">
                No Products found.
            </td>
        </tr>
        `;
        return;
    }

    tbody.innerHTML = list.map(function (p) {

        const price = adminPrice[p.category] || 0;
        const category = adminCategoryLabels[p.category]
             || p.category;

             return `
             <tr id="row-${p.id}">
             <td class="admin-td-name">${p.name}</td>
             <td>${category}</td>
             <td>${p.unit}</td>
             <td id="price-display-${p.id}">
             ${format(Price)}
             </td>
             </td>
             <button class="admin-edit-btn"
             onclick="editPrice('${p.id}', ${price})">
             Edit
             </button>
             </td>
             </tr>
             `;
    }).join("");

 }

 /*--------Edit price inline -------
 Replace the price cell with an input and changes the Edit button save */

 function editPrice(productId, currentPrice) {

    // Replace price display with input
    document.getElementById("price-display-" + productId)
    .innerHTML = `
    <input type="number"
    id="price-input-${productId}"
    class="admin-price-input"
    value="${currentPrice}" />

    `;


    //Replace Edit button with save button
    const row = document.getElementById("row-" + productId);
    const actionCell = row.querySelector("td:last-child");
    actionCell.innerHTML = `
    <button class="admin-save-btn"
    onclick="savePrice('${productId}')">
    Save
    </button>
    <button class="admin-cancel-btn"
    onclick="renderPriceTable()">
    Cancel
    </button>
    `;
 }


 /*------- Save updated price ---------- */
 function savePrice(productId) {

    const input = document.getElementById("price-input-" + productId );
    const newPrice = Number(input.value);


    if (!newPrice ||newPrice <= 0) {
        alert("please enter a valid price.");
        return;
    }

    //find the product category
    const product = adminProducts.find(function (p) {
        return p.id === productId;
    });

    if (product) {
        //update the price for this category
        adminPrices[product.category] = newPrice;
    }

    //Re-render the table
    renderPriceTable();

    alert("price updated successdully.");
 }

 /*------- Render Products Table ---- */
 function renderProductTable(filter) {

    const tbody = document.getElementById("product-tBody");
    const search = filter ? filter.toLowerCase().trim() : "";

    let List = adminProducts;

    if (search !== "") {
        list = list.filter(function (p) {
            return p.name.toLowerCase().includes(search);
        }) ;
    }

    if (list.length === 0) {
        tbody.innerHTML = `
        <tr>
        <td colspan="5" class="admin-empty">
            No products found.
            </td>
            </tr>

        `;
        return;
    }


    tbody.innerHTML = list.map(function (p) {

        const price = adminPrices[p.category] || 0;
        const category = adminCategoryLabels[p.category]
        || p.category;

        return `
        <tr>
        <td class="admin-td-name">${p.name}</td>
        <td>${category}</td>
        <td>${p.unit}</td>
        <td>${formatprice(price)}</td>
        <td>
        <button class="admin-delete-btn"
        onclick="deleteProduct('${p.id}')">
        Remove
        </button>        
        `;
    }).join("");
 }

 /*----- Delete product ------ */
 function deleteProduct(productId) {

    const confirm = window.confirm(
      "Are you sure you want to remove this product? "
    );

    if (!confirm) return;

    adminProducts = adminProducts.filter(function (p) {
        return p.id !== productId;
    });

    renderProductTable();
    renderPriceTable();
 }

 /*------ Show / hide add form ------- */
 function showAddForm() {
    document.getElementById("admin-add-form").style.display = "block";
 }

 function hideAddForm() {
    document.getElementById("admin-add-form").style.display = "none";
    document.getElementById("new-name").value  ="";
    document.getElementById("new-price").value  ="";
    document.getElementById("new-category").value  = "";
    document.getElementById("new-unit").value   = "Tray";
 }

 /*-------- Add new product ---------- */
 function addNewProduct() {

    const name  = document.getElementById("new-name").value.trim();
    const category  = document.getElementById("new-category").value;
    const  unit = document.getElementById("new-unit").value;
    const price  = Number(document.getElementById("new-price").value);

    if (!name || !category || !price || price <= 0) {
        alert("please fill in all fields with valid values");
        return;
    }

    // Add to the product list
    adminProducts.push({
        id       : newId,
        name       : name,
        category   : category, 
        unit        : unit
    });


    //Update the price for the category
    adminPrices[category] = price;


    //Re-render both tables
    renderProductTable(); 
    renderProductTable();
    
    //Hide and reset the form
    hideAddForm();
 }

 /*---- Wire up search inputs ---- */
 document.getElementById("price-search")
    .addEventListener("input", function () {
        renderPriceTable(this.value);
    });

    document.getElementById("product-search")
    .addEventListener("input", function () {
        renderProductTable(this.value);
    });


