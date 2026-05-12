/*=======================================================
FORGOT PASSWORD - FORM LOGIC

Handles two states:
1. Default - user enters their email and submit the form.

2. success - form hides and a confirmation
message shows with the email they entered.

In stage 3 this will connect to the backend and actually send a reset email. For 
now it just simulates the flow visually.

=========================================================*/

/*---------Handle form submission ------- 
Intercpts the form submit, grabs the email,
shows the success state with the email displayed.*/

document.addEventListener ("DOMContentLoaded", function () {
    const form = document.getElementById("forgot-form");

    form.addEventListener("submit", function (e) {
        
        //stop the page from reloading on submit
        e.preventDefault();

        // Grab the email the user typed
        const email = document.getElementById("forgot-email").value;

        //show it in the success message 
        document.getElementById("forgot-email-display").textContent = email;

        //Hide the form state
        document.getElementById("forgot-form-state").style.display = "none";

        //show the success state
        document.getElementById("forgot-success-state").style.display ="block";

    });
});

/*----- Reset form back to default ------
  Called when user clicks "Try a different email".
  Hide the success state and shows the form again. */

  function resetForgotForm() {
    
    //clear the email input
    document.getElementById("forgot-email").value = "";

    //Hide success state
    document.getElementById("forgot-success-state").style.display = "none";

    //show form state
    document.getElementById("forgot-form-state").style.display = "block";


  }
