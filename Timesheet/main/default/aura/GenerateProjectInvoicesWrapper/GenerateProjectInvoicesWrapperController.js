({
    init : function(component, event, helper) {
        // Defer startFlow until after the lightning:flow component has fully rendered.
        // Calling it synchronously in init causes "An unhandled fault has occurred in this flow".
        window.setTimeout(
            $A.getCallback(function() {
                var flow = component.find("flowData");
                if (flow && component.isValid()) {
                    flow.startFlow("Generate_Project_Invoices");
                }
            }), 0
        );
    },
    handleStatusChange : function(component, event, helper) {
        var status = event.getParam("status");
        if (status === "FINISHED" || status === "FINISHED_SCREEN") {
            helper.navigateToList(component, true);
        }
    },
    handleClose : function(component, event, helper) {
        helper.navigateToList(component, false);
    }
})
