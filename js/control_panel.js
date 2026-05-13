/*=============================================
CONTROL PANEL- OWNER MONITORING LOGIC

shows the owner all prices changes made 
by the sales managers accross all branches.

In stage 3 this pulls from the database.
for now it uses simulated log data.

================================================
*/

/*------ Simulated change log 
Each entry represents one price update made by 
a seles manager
Fields:
-datetime : when it happened 
-manager : who made the change 
- branch : which branch they work at
-product : what product was changed 
-category : product category 
-old Price : price before the change 
- new Price : price after the change
*/


const changeLog = [
    {

        datetime :"2026-05-12 09:14",
        manager : "Chukuemeka",
        branch : "Owerri",
        product : "Heineken RGB - 60CL",
        category : "Beer & Stout",
        oldPrice :   1200,
        newPrices : 15000,
    },


    {

        datetime :"2026-05-12 10:32",
        manager : "Adaeze",
        branch : "Onisha",
        product : "Four Cousins Sweet Red",
        category : "Wines",
        oldPrice :   40000,
        newPrices : 42500,
    },


    {

        datetime :"2026-05-12 14:14",
        manager : "Emeka",
        branch : "Port Harcourt",
        product : "Hennessy VS - 75cl",
        category : "Spirit",
        oldPrice :   90000,
        newPrices : 95000,
    },


    {

        datetime :"2026-05-12 11:14",
        manager : "Chukuemeka",
        branch : "Owerri",
        product : "Star Lager RGB",
        category : "Beer & Stout",
        oldPrice :   9500,
        newPrices : 9800,
    },


    {

        datetime :"2026-05-12 09:14",
        manager : "Ngozi",
        branch : "Ikeja Lagos",
        product : "Maltina Rgb",
        category : "Malt Drink",
        oldPrice :   8000,
        newPrices : 8400,
    },


    {

        datetime :"2026-05-12 09:14",
        manager : "Adaeze",
        branch : "Onitsha",
        product : "Red Bull Energy - 250ml",
        category : "RTD & Energy",
        oldPrice :   24000,
        newPrices : 26000,
    },


    {

        datetime :"2026-05-09 15:14",
        manager : "Emeka",
        branch : "Port Harcourt",
        product : "jigga Bitters - 750ml",
        category : "Bitters",
        oldPrice :   17000,
        newPrices : 18000,
    },


    {

        datetime :"2026-05-09 10:14",
        manager : "Ngozi",
        branch : "Ikeja Lagos",
        product : "Gordon's Dry Gin - 75cl",
        category : "Spirits",
        oldPrice :   92000,
        newPrices : 95000,
    }
];

/*------ Format Price ------- */
function cpFormatPrice(amount) {
    return "₦" + Number (amount).toLocaleString();
}

/*------- Format price change ----- 
Show +X% in red or -X% in  green
*/
function formatChange(oldPrice, newPrice) {
  
    const diff  = newPrice - oldPrice;
    const percent = ((diff / oldPrice) *100).toFixed(1);
    const sign = diff > 0 ? "+" : "";
    const color = diff > 0 ? "#8b1d1d" : "#0d5c2f";

    return <span style="color:${color};font-weight:700;">
        ${sign}${percent}%
    </span>;
}


/*----- Render KPI card ---- */
function renderKPIs() {


//Total products from global products array
document.getElementById("kpi-products").textContent
                = products.length;


// Total updates this week
document.getElementById("Kpi-updates").textContent
        = changeLog.length;
        
//Last update timestamp
document.getElementById("kpi-last").textContent
     = changeLog[0].datetime;

     //Count unique managers 
     const managers = [...new Set(
        changeLog.map(function (c) {return c.manager; })
     )];
     document.getElementById("kpi-managers").textContent
            =managers.length;
    }

/*----- Render activity feed ----- */
function renderFeed() {

    const feed = document.getElementById(cp-feed);

    feed.innerHTML = changeLog.slice(0, 6).map(function (c) {

    const diff  = c.newPrice - c.oldPrice;
    const sign  = diff > 0 ? "+" : "";
    const color  = diff > 0 ? "#8b1d1d" : "#0d5c2f"


    return `
       <div class="cp-feed-item">
        <div class="cp-feed-dot"
        style="background:${color};"></div>
        <div class="cp-feed-content">
        <p class="cp-feed-text">
          <strong>${c.manager}</strong> 
          updated <strong>${c.product}</strong>
          from ${cpFormatPrice(c.oldPrice)}
          to ${cpFormatPrice(c.newPrice)} 
        </p>
        <p class="cp-feed-meta">
            ${c.branch} &middot; ${c.datetime}
        </p>
        </div>
       </div>
       `;

    }).join("");

}

/*----- Render summary card ----- */
function renderSummary() {


// Highest price change by amount
const highest = changeLog.reduce(function (max, c) {
    return (c.newPrice - c.oldPrice) > (max.newPrice - max.oldPrice)
        ? c : max;
});
document.getElementById("summary-highest").textContent
    = highest.product ;


    
// Most active manager
const managerCount = {};
changeLog.forEach(function (c) {
    managerCount[c.manger] = (managerCount[c.manager] || 0) + 1
});
const topManager = Object.keys(managerCount).reduce (
      function (a, b) {
        return managerCount[a] >managerCount[b] ? a : b;
      }
);
document.getElementById("summary-manager").textContent
   = topManager + "(" + managerCount[topManager] + "changes)";









}








