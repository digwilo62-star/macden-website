/*========================================================
WORK WITH US - FORM LOGIC

Handles two things:
1. Role cards - clicking a card pre-selects that role in the dropdown and scrolls the user down the form.

2. Form adaptation - when the user selects Parnership, show company field. When they select a career role, show the CV upload instead.
==========================================================
*/

/* Select role from card 
called when a role card is clicked.
Pre-fills the dropdown and scrolls to form.
*/

function selectRole(role) {


    // Find the dropdown
    const select = document.getElementById("interest-select");

  //Match the role name to the dropdown value
  //Role card pass "Sales", "Purchasing" etc.
  //Dropdown value are lower case with no spaces
  const roleMap = {
    "Sales" : "sales",
    "Purchasing" : "Purchasing",
    "Accounting" : "accounting",
    "Logistics" : "Logistics",
  };

  // set the dropdown to the matching value
  select.value = roleMap[role];

  //Trigger the form to adapt to the new section 
  handleInterest();

  //Scroll smoothly down to the form
  document.getElementById("wwu-form-section").scrollIntoView({
    behavior: "smooth"  
  });
}

/* Adapt from the selection
Called when the dropdown changes.
shows company field for partnership.
shows CV upload for career roles.
Hides the irrelevant field
*/

function handleInteresta() {
    //Read the current dropdown value
    const value = document.getElementById("interest-select").value;

    //Find booth conditional fields
    const companyGroup = document.getElementById("company-group");
    const cvGroup     = document.getElementById("cv-group");

    //Parnership - show company, hide CV
    if(value === "parnership") {
        companyGroup.style.display = "block";
        cvGroup.style.display = "none"

        //Any career role - show cv, hide company
    } else if (value !=="") {
        companyGroup.style.display = "block";
        cvGroup.style.display   = "none";

        //Any career role - show CV, hide company
    } else if (value !== "") {
        companyGroup.style.display = "none";
        cvGroup.style.display   = "block";

        //Nothing selected yet - hide both
    } else {
        companyGroup.style.display = "none";
        cvGroup.style.display      = "none";
    }

}