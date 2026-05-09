/*=====================================================
PRODUCT DATA
The MACDEN catalogue used by the products page.

Each product object has four fields:
id    - unique identifier (p001, p002, ....)
name  - display name shown on the card
category  - matches a filter-chip data-category
unit   - "Tray" or "Crt" (cartoon / crate)

Categories must match the chip data-category values:
wines, spirits, bitters, beer-stout, malt-drink,
rtd-energy
*/ 

const products = [
    //=====  WINES ======
    {
        id: "p001", 
        name: "Four Cousins Sweet Red Wine - 750ml x 6",
        category: "wines",
        unit: "Tray"
    },


    {
        id: "p002", 
        name: "Bottega Gold - 750ml",
        category: "wines",
        unit: "Tray"
    },

    //======== SPIRITS ============
    {
        id: "p003", 
        name: "Gordon's Dry Gin Moringa Citrus - 75cl",
        category: "spirits",
        unit: "Crt"
    },

    
    {
        id: "p004", 
        name: "Kings Kestrel Whiskey - 750ml x 6",
        category: "spirits",
        unit: "Tray"
    },


    //====== BITTERS=============
    {
        id: "p005", 
        name: "Jigga Bitters - 750ml",
        category: "bitters",
        unit: "Tray"
    },

    {
        id: "p006", 
        name: "1960 Rootz Bitters Black - 750ml",
        category: "bitters",
        unit: "Tray"
    },

//========== BEER & STOUT ============
  {
        id: "p007", 
        name: "Star Lager RGB",
        category: "beer-stout",
        unit: "Crt"
    },
    
      {
        id: "p008", 
        name: "Heineken RGB - 60cl",
        category: "beer-stout",
        unit: "Crt"
    },
    
//========= MALT DRINKS ================
{
    id: "p009",
    name: "malt-drinks",
    unit: "Crt"
},

{
    id: "p010",
    name: "Amstel Malt RGB",
    category: "malt-drinks",
    unit: "Crt"
},

//======== RTD & ENERGY ================
{
    id: "p011",
    name: "smirnoff Ice 30cl RGB",
    category: "rtd-energy",
    unit: "Crt",
},

{
    id: "p012",
    name: "Red Bull Energy Drink Can - 250ml",
    category: "rtd-energy",
    unit: "Crt",
}




]